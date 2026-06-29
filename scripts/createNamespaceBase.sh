#!/bin/bash

TENANT_A="tenant-a"
USER_A="alice"

TENANT_B="tenant-b"
USER_B="bob"

CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT_B64=$(kubectl get configmap kube-root-ca.crt -n default -o jsonpath='{.data.ca\.crt}' | openssl base64 -A)

echo "Creating namespaces, users, and RBAC configurations for tenants..."

# Namespace Creation

echo "Namespaces to be created: $TENANT_A, $TENANT_B"
kubectl create namespace $TENANT_A --dry-run=client -o yaml | kubectl apply -f - # dry run to avoid errors if namespace already exists, then apply the configuration
kubectl create namespace $TENANT_B --dry-run=client -o yaml | kubectl apply -f -


setup_tenant() {
    local NAMESPACE=$1
    local USERNAME=$2
    local CSR_NAME="${USERNAME}-csr"
    local KUBECONFIG_FILE="kubeconfig-${USERNAME}"

    echo "--- Configuring user $USERNAME in namespace $NAMESPACE ---"
    rm "$KUBECONFIG_FILE"
    # Generate private and public key

    openssl genrsa -out ${USERNAME}.key 2048
    openssl req -new -key ${USERNAME}.key -out ${USERNAME}.csr -subj "/CN=${USERNAME}/O=${NAMESPACE}-group"

    kubectl delete csr $CSR_NAME --ignore-not-found

    cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $CSR_NAME
spec:
  request: $(cat ${USERNAME}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

    kubectl certificate approve $CSR_NAME
    while [ -z "$(kubectl get csr $CSR_NAME -o jsonpath='{.status.certificate}')" ]; do
        sleep 1
    done
    kubectl get csr $CSR_NAME -o jsonpath='{.status.certificate}'| base64 -d > ${USERNAME}.crt

    
    echo "Crete new context and import the new user to the cluster..."  
    
    kubectl config set-credentials "$USERNAME" \
        --client-certificate="${USERNAME}.crt" \
        --client-key="${USERNAME}.key" \
        --embed-certs=true \
        --kubeconfig="$KUBECONFIG_FILE"
    
      kubectl config set-cluster minikube \
        --server="$CLUSTER_SERVER" \
        --kubeconfig="$KUBECONFIG_FILE"
      kubectl config set clusters.minikube.certificate-authority-data "$CA_CERT_B64" \
        --kubeconfig="$KUBECONFIG_FILE"

    kubectl config set-context "${USERNAME}-context" \
        --cluster=minikube \
        --namespace="$NAMESPACE" \
        --user="$USERNAME" \
        --kubeconfig="$KUBECONFIG_FILE"
    
    kubectl config use-context "${USERNAME}-context" --kubeconfig="$KUBECONFIG_FILE"

    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $NAMESPACE
  name: tenant-admin-role
rules:
- apiGroups: ["", "apps", "batch", "extensions"]
  resources: ["deployments", "replicasets", "pods", "pods/exec", "services", "configmaps", "secrets", "serviceaccounts", "endpoints", "persistentvolumeclaims", "jobs", "cronjobs"]
  verbs: ["create", "get", "list", "watch", "update", "patch", "delete"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["create", "get", "list", "watch", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-admin-binding
  namespace: $NAMESPACE
subjects:
- kind: User
  name: $USERNAME
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-admin-role
  apiGroup: rbac.authorization.k8s.io
EOF


    rm ${USERNAME}.key ${USERNAME}.csr ${USERNAME}.crt
    echo "User $USERNAME configured successfully in namespace $NAMESPACE. Kubeconfig saved to $KUBECONFIG_FILE"
    echo "------------------------------------------------------------"
}



setup_tenant $TENANT_A $USER_A
setup_tenant $TENANT_B $USER_B