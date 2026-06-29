#!/bin/bash

minikube start --cni=calico --container-runtime=containerd --driver=docker --static-ip=192.168.49.2 --extra-config=controller-manager.horizontal-pod-autoscaler-sync-period=20s # --nodes=3 
minikube addons enable metrics-server
kubectl wait --namespace kube-system --for=condition=Available deployment/metrics-server --timeout=90s
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--metric-resolution=20s"}]'
minikube addons enable ingress
minikube ssh -n minikube     -- sudo mount -o remount,nosuid,nodev,noexec,size=50% /dev/shm # expand /dev/shm size to aovoid error when kata create kvm2 vm
minikube ssh -n minikube-m02 -- sudo mount -o remount,nosuid,nodev,noexec,size=50% /dev/shm 
minikube ssh -n minikube-m03 -- sudo mount -o remount,nosuid,nodev,noexec,size=50% /dev/shm
#echo "Waiting for the calico pod to be ready before installing Kata Containers..."
kubectl wait --namespace ingress-nginx \
--for=condition=ready pod \
--selector=app.kubernetes.io/component=controller \
--timeout=30s

export VERSION=$(curl -sSL https://api.github.com/repos/kata-containers/kata-containers/releases/latest | jq .tag_name | tr -d '"')
export CHART="oci://ghcr.io/kata-containers/kata-deploy-charts/kata-deploy"
helm install kata-deploy "${CHART}" --version "${VERSION}"

./scripts/createNamespaceBase.sh # create user and namespace for the 2 tenants
