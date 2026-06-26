#!/bin/bash

minikube start --memory=6144 --cni=calico --disk-size="2000mb" --disk-size="11000mb" --nodes=3 --container-runtime=containerd
minikube addons enable metrics-server
