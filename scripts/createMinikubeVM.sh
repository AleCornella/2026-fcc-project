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

EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Minikube_VM" -l ID --csv  | tail -n +2)
if [[ -n "$EXISTING_TEMPLATE_ID" ]]; then
    TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
    if [[ "$FORCE_TEMPLATE_RECREATE" == true ]]; then
        echo "Forcing recreation of the templates..."
        onetemplate delete "$EXISTING_TEMPLATE_ID"
        bash scripts/createGoldenImageMiniKube.sh -f
        EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Minikube_VM" -l ID --csv  | tail -n +2)
        TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
    fi
else
    bash scripts/createGoldenImageMiniKube.sh
    EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Minikube_VM" -l ID --csv  | tail -n +2)
    TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
fi

OUTPUT=$(onetemplate instantiate "$TEMPLATE_ID")
RUNNING_VM_ID=$(echo "$OUTPUT" | awk '{print $3}')
VM_IP=$(onevm show -j "$RUNNING_VM_ID" | jq -r '.VM.TEMPLATE.NIC[0].IP')
echo "Minikube VM is running with ID: $RUNNING_VM_ID and IP: $VM_IP"