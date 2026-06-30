#/bin/bash

KUBECONFIG=./kubeconfig-bob kubectl delete job cpu-hog --ignore-not-found
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
ALLOCATABLE_RAW=$(kubectl get nodes $NODE_NAME -o jsonpath='{.status.allocatable.cpu}')

if [[ $ALLOCATABLE_RAW == *m ]]; then
    TOTAL_MILLI=${ALLOCATABLE_RAW%m}
else
    TOTAL_MILLI=$((ALLOCATABLE_RAW * 1000))
fi

ALLOCATED_RAW=$(kubectl describe node $NODE_NAME | awk '/Allocated resources:/,/[E|e]vents:/' | awk '$1=="cpu" {print $2}')

if [[ -z "$ALLOCATED_RAW" || "$ALLOCATED_RAW" == "0" ]]; then
    ALLOCATED_MILLI=0
elif [[ $ALLOCATED_RAW == *m ]]; then
    ALLOCATED_MILLI=${ALLOCATED_RAW%m}
else
    ALLOCATED_MILLI=$((ALLOCATED_RAW * 1000))
fi

FREE_MILLI=$((TOTAL_MILLI - ALLOCATED_MILLI))
FREE_MILLI="${FREE_MILLI}m"
sed "s/MAX_CPU_PLACEHOLDER/$FREE_MILLI/g" minikube/deployments/job-b.yaml | KUBECONFIG=./kubeconfig-bob kubectl apply -f -
