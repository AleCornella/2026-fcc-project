#!/bin/bash
KUBECONFIG=./kubeconfig-alice kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
KUBECONFIG=./kubeconfig-alice kubectl apply -f hpas/hpa-a.yaml
KUBECONFIG=./kubeconfig-alice kubectl apply -f ingress/ingress-tenant-a.yaml