#!/bin/bash

minikube start --cni=calico --nodes=3 --container-runtime=containerd --driver=docker
minikube addons enable metrics-server
minikube ssh -n minikube     -- sudo mount -o remount,nosuid,nodev,noexec,size=50% /dev/shm # expand /dev/shm size to aovoid error when kata create kvm2 vm
minikube ssh -n minikube-m02 -- sudo mount -o remount,nosuid,nodev,noexec,size=50% /dev/shm 
minikube ssh -n minikube-m03 -- sudo mount -o remount,nosuid,nodev,noexec,size=50% /dev/shm
minikube addons enable metrics-server
echo "Waiting for the calico pod to be ready before installing Kata Containers..."
sleep 120

export VERSION=$(curl -sSL https://api.github.com/repos/kata-containers/kata-containers/releases/latest | jq .tag_name | tr -d '"')
export CHART="oci://ghcr.io/kata-containers/kata-deploy-charts/kata-deploy"
helm install kata-deploy "${CHART}" --version "${VERSION}"

./scripts/createNamespaceBase.sh # create user and namespace for the 2 tenants

3.29 m