#!/bin/bash


FORCE_TEMPLATE_RECREATE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--force) 
            FORCE_TEMPLATE_RECREATE=true 
            shift
            ;;
        -h|--help)
            echo "Use: ./script.sh -f/--force to force the recreation of the templates and images."
            ;;
        *) 
            echo "Error: Unknown parameter passed: $1"
            exit 1 
            ;;
    esac
done

# Download the Ubunut image on which we will install MiniKube
EXISTING_IMAGE_ID=$(oneimage list -f NAME="Ubuntu 24.04" -l ID --csv  | tail -n +2)


if [[ -n "$EXISTING_IMAGE_ID" ]]; then
    export IMAGE_ID="$EXISTING_IMAGE_ID"
    export IMAGE_NAME=$(oneimage list -f NAME="Ubuntu 24.04" -l NAME --csv  | tail -n +2)
    
    
else
    VM_IMAGE_ID=$(onemarketapp list -f NAME="Ubuntu 24.04" -l ID --csv | tail -n +2)
    export IMAGE_NAME=$(onemarketapp list -f NAME="Ubuntu 24.04" -l NAME --csv | tail -n +2)
    EXPORT_OUT=$(onemarketapp export "$VM_IMAGE_ID" "$IMAGE_NAME" -d 1)
    export IMAGE_ID=$(echo $EXPORT_OUT | awk '{print $3}')
    echo "Downloading image with ID: $VM_IMAGE_ID and name: $IMAGE_NAME"

    # Wait for the disk to be downloaded
    while true; do
        STATUS=$(oneimage show "$IMAGE_ID" -j | jq -r '.["IMAGE"]["STATE"]')
        if [[ "$STATUS" != '4' ]]; then
            break
        fi
        echo "Waiting for disk to be downloaded..."
        sleep 20
    done
fi


EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Ubuntu+minikube" -l ID --csv  | tail -n +2)
TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
if [[ -n "$EXISTING_TEMPLATE_ID" ]]; then
    echo "Template already exists with ID: $EXISTING_TEMPLATE_ID. To force the recreation of the template, use the -f/--force option."
    if [[ "$FORCE_TEMPLATE_RECREATE" == true ]]; then
        echo "Forcing recreation of the template..."
        onetemplate delete "$EXISTING_TEMPLATE_ID"
        export STARTUP_SCRIPT=$(base64 -w 0 "scripts/openNebula/installDockerAndMinikube.sh")
        envsubst '${STARTUP_SCRIPT},${IMAGE_NAME},${IMAGE_ID}' < templates/UbuntuMinikube.tmpl > MinikubeVM.tmpl
        OUTPUT=$(onetemplate create MinikubeVM.tmpl)
        TEMPLATE_ID=$(echo "$OUTPUT" | awk '{print $2}')
    fi
else
    # CREATE TEMPLATE
    export STARTUP_SCRIPT=$(base64 -w 0 "scripts/openNebula/installDockerAndMinikube.sh")
    envsubst '${STARTUP_SCRIPT},${IMAGE_NAME},${IMAGE_ID}' < templates/UbuntuMinikube.tmpl > MinikubeVM.tmpl
    OUTPUT=$(onetemplate create MinikubeVM.tmpl)
    TEMPLATE_ID=$(echo "$OUTPUT" | awk '{print $2}')
fi

# CREATE FIRST VM
OUTPUT=$(onetemplate instantiate "$TEMPLATE_ID")
RUNNING_VM_ID=$(echo "$OUTPUT" | awk '{print $3}')

while [[ "$(onevm show -j "$RUNNING_VM_ID"  | jq -r '.VM.STATE')" != "3" && "$(onevm show -j "$RUNNING_VM_ID"  | jq -r '.VM.LCM_STATE')" != "3" ]]; do
    echo "Waiting for the VM to be in RUNNING state..."
    sleep 5
done

VM_IP=$(onevm show -j "$RUNNING_VM_ID" | jq -r '.VM.TEMPLATE.NIC[0].IP')

while true; do

    ssh -q -o StrictHostKeyChecking=no -o BatchMode=yes minikube@"$VM_IP" "minikube version" > /dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        break
    fi
    echo "Waiting for the VM to install Docker and MiniKube..."
    sleep 10
done

# copy the kubeconfig folder from the host to the VM
echo "Copying the minikube folder to the VM..."
scp -r /minikube "minikube@"$VM_IP":~/minikube"
ssh -q -o StrictHostKeyChecking=no -o BatchMode=yes minikube@"$VM_IP" "ls -l"
echo "Copying the scripts folder to the VM..."
scp -r /scripts/minikube "minikube@"$VM_IP":~/scripts/minikube"
ssh -q -o StrictHostKeyChecking=no -o BatchMode=yes minikube@"$VM_IP" "ls -l"
onevm stop "$RUNNING_VM_ID"
while [[ "$(onevm show -j "$RUNNING_VM_ID"  | jq -r '.VM.STATE')" != "4" ]]; do
    echo "Waiting for the VM to be in STOPPED state..."
    sleep 2
done

# SAVE THE DISK AS A NEW GOLDEN IMAGE
EXISTING_IMAGE_ID=$(oneimage list -f NAME="minikube-disk" -l ID --csv  | tail -n +2)
if [[ -n "$EXISTING_IMAGE_ID" ]]; then
    echo "Image 'minikube-disk' already exists with ID: $EXISTING_IMAGE_ID. To force the recreation of the image, use the -f/--force option."
    if [[ "$FORCE_TEMPLATE_RECREATE" == true ]]; then
        echo "Forcing recreation of the image..."
        oneimage delete "$EXISTING_IMAGE_ID"
        sleep 2
    else
        exit 0
    fi
fi

OUTPUT=$(onevm disk-saveas "$RUNNING_VM_ID" 0 "minikube-disk")
export IMAGE_ID=$(echo "$OUTPUT" | awk '{print $3}')

while [[ "$(onevm show -j "$RUNNING_VM_ID"  | jq -r '.VM.STATE')" != "4" ]]; do
    echo "Waiting for the VM to be in STOPPED state..."
    sleep 2
done

# CREATE GOLDEN IMAGE TEMPLATE
EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Minikube_VM" -l ID --csv  | tail -n +2)
TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
if [[ -n "$EXISTING_TEMPLATE_ID" ]]; then
    echo "Template already exists with ID: $EXISTING_TEMPLATE_ID"
    if [[ "$FORCE_TEMPLATE_RECREATE" == true ]]; then
        echo "Forcing recreation of the template..."
        onetemplate delete "$EXISTING_TEMPLATE_ID"
        IMAGE_ID=$(echo "$OUTPUT" | awk '{print $3}')
        envsubst '${IMAGE_ID}' < templates/minikubeVM.tmpl > MinikubeVM.tmpl
        OUTPUT=$(onetemplate create MinikubeVM.tmpl)
        TEMPLATE_ID=$(echo "$OUTPUT" | awk '{print $2}')
    else
        echo "Template already exists. To force the recreation of the template, use the -f/--force option."
        exit 0
    fi
else
    # CREATE TEMPLATE
    IMAGE_ID=$(echo "$OUTPUT" | awk '{print $3}')
    envsubst '${IMAGE_ID}' < templates/minikubeVM.tmpl > MinikubeVM.tmpl
    OUTPUT=$(onetemplate create MinikubeVM.tmpl)
    TEMPLATE_ID=$(echo "$OUTPUT" | awk '{print $2}')
fi

onevm terminate "$RUNNING_VM_ID"