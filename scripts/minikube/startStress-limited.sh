#/bin/bash

KUBECONFIG=./kubeconfig-bob kubectl delete job cpu-hog --ignore-not-found
KUBECONFIG=./kubeconfig-bob kubectl apply -f deployments/job-b-limited.yaml
