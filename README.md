# Fog and Cloud Computing Project

This project demonstrates how a **noisy neighbor** can affect the performance of a Kubernetes workload and how to provide isolation both between tenants and within the same tenant.

We deploy a Minikube cluster inside a VM managed by OpenNebula.

## Goal
For the **noisy neighbor** we want to:
- Generate artificial load to simulate a noisy neighbor
- Compare the behavior of the system before and during the stress phase

For the **isolation** we want to:
- create a Calico network policies to block tenant-to-tenant comunication
- use **Kata container** to isolate the pod

## Repository Layout

- `minikube/` - all the Kubernetes yaml files
- `scripts/`     - Automation scripts for setup, deployment, and stress testing
- `templates/`   - VM and environment templates used to create the lab environment.
- `python/` - Locust file used to test the performance of Tenant A. The file was created by google to simulate realistic traffic against the Onine Boutique demo e-commerce.


## Requirements

- A machine running OpenNebula cabable of provisioning:
    - minimum: a VM with 4 cores and 12 GB of RAM
    - raccomended: a VM with 8 cores and 16 GB of RAM
- Locust installed on the Host machine


## Environment Setup Steps
### 1. Locust
On your local machine:
```bash
pip install locust
```

### 2. Set Up OpenNebula (if not already installed)
The project was created with OpenNebula running inside a local ubuntu VM using QEMU and installed with miniONE. If you don't have a OpenNebula installation ready, you can follow the official instruction at this [link](https://docs.opennebula.io/7.2/getting_started/try_opennebula/opennebula_sandbox_deployment/deploy_opennebula_onprem_with_minione/).
Once you have a working installation, proceed to the next step.


### 3. Copy Files to OpenNebula Host
Run the following command to copy all necessary files into the OpenNebula host:
```bash
./scripts/copy_on_opennebula.sh
```
Then SSH into your OpenNebula machine.


### 4. Create the Minikube VM
Inside the OpenNebula host, run the following command. The script must be executed by a user with OpenNebula API permissions (e.g., root or minione if installed via miniONE).

> [!NOTE]
> The script automatically configures iptables and NAT rules to allow access to services running on the Minikube cluster. It is designed for setups where OpenNebula is installed as a QEMU VM on a Linux host. For different setups, you can use the `--no-nat-config` flag to skip iptables changes and use an SSH tunnel instead.

```bash
cd FCC-Project/
(sudo) ./scripts/openNebula/createMinikubeVM.sh
```

**Optional flags:**
- You can use the argument `-f` or `--force` to force the script to recreate the templates and images.
> [!CAUTION]
> This will delete:
> - all the templates named: `Ubuntu+minikube` and `Minikube_VM`
> - all the images named: `minikube-disk`


If the script fails, you can manually create the VM via the OpenNebula Sunstone UI:
- Base image: Ubuntu 24.04
- 8 vCPUs, 16 GB RAM, 50 GB storage
- CPU mode: 'host-passthrough'

Then set up iptables and NAT manually:
```bash
./scripts/openNebula/setNAT.sh [YOUR_MINIKUBE_VM_IP]
```

### 5. Start Minikube
Once the Minikube VM is running, SSH into it and start Minikube:
```bash
./scripts/startMinikube.sh
```

The script will:
- start Minikube
- enable Kata container, Calico CNI e the Nginx ingress
- create two user and namespcaces representing two different tenants sharing the same cluster

## Deploy the Workloads
Deploy Alice's application (namespace tenant-a) using the Google Online Boutique for a realistic microservices demo:
```bash
./scripts/deploy-a.sh
```
Afeter around 90s, the time the deplyment is started on the cluster, visit `*openNebulaIP*:8080` in your browser, you should see the Google Boutique home page.


## Resource Governance
### Measure Normal Response Time
You can verify the normal response time with Locust.
To start Locust:
```bash
cd python
locust
```
Oen in your browser the locus interface `http://127.0.0.1:8089` and configure:
-  Number of user: 150
-  Rump up: 10
-  Host: `http://[OpenNebulaIP]:8080`

### Simulate a Noisy Neighbor
Stop the Locust test if running, then launch a resource-exhausting job from tenant B:
```bash
./scripts/startStress.sh
```
Wait a few seconds for the job to start and then run again the Locust test against tenant A's boutique.

Monitor CPU usage on the node with:
```bash
kubectl describe node | grep -A 5 "Allocated resources:"
```
Now the response time will be much longer, the website will also feel slower in the browser.

The stress test will automatically stop after 5 minutes. To stop it manually:
```bash
kubectl delete job cpu-hog -n tenant-b
```

## Mitigation
### Apply LimitRange
To limit resource usage per pod in tenant B's namespace:
```bash
kubectl apply -f minikube/limits/tenant-b-limit-range.yaml
```
Now tenant B can no longer create job that take more than 1 full CPU. However, they can still exhaust resources by launching multiple jobs:

Before running again the script wait a couple of minutes until the HPA of the tenant A will downscale the deplyment.
```
./scripts/startStress-limited.sh
```
Running Locust again will still show performance degradation.

### Apply ResourceQuota
Enforce a total resource quota for tenant B's namespace:
```bash
kubectl apply -f minikube/quota/tenant-b-quota.yaml
```
Rerun the limited stress test:
```bash
./scripts/startStress-limited.sh
```
Now Locust results should show response times similar to the baseline demonstrating how LimitRange and ResourceQuota together can mitigate noisy neighbor issues.

## Security Isolation
### Test Tenant Isolation (Without Policies)
First, verify that tenants can communicate by default:
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/deployments/deployment-b.yaml
SERVER_IP="$(KUBECONFIG=./kubeconfig-bob kubectl get pod -l app=bob-web-server -o jsonpath='{.items[0].status.podIP}')"
KUBECONFIG=./kubeconfig-alice kubectl apply -f minikube/deployments/pod-a.yaml
KUBECONFIG=./kubeconfig-alice kubectl exec -it pod-client-a -- wget -O - http://$SERVER_IP
```
You should see the nginx welcome page, confirming that tenants are not isolated by default.

### Apply Network Policies
We prepared two network policies. One is the DenyAll that is applied to both tenant namespace. For tenant A we add a second policy to allow incoming traffic only on the frontend pos, gaining connection to the website.
```bash
KUBECONFIG=./kubeconfig-alice kubectl apply -f minikube/network-policies/tenant-a-policy.yaml
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/network-policies/tenant-b-policy.yaml
```
Now wget to the nginx pod will fail, but the boutique website remains accessible.

### Pod-Level Isolation with Kata Containers
Kata Containers provide stronger isolation by running each pod in a lightweight VM. We'll demonstrate this by deploying a privileged pod with and without Kata.

**Without Kata (vulnerable):**
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/deployments/vulnerable-deployment.yaml
KUBECONFIG=./kubeconfig-bob kubectl exec -it privileged-without-kata -- bash
```
Inside the pod, mount the host root filesystem:
```bash
lsblk -l
mkdir /host-root
mount /dev/vda1 /host-root
ls -la /host-root
ls -la /host-root/home
```
You can see host files — this is a security risk.

**With Kata (secure):**
Now exit, delete the pod, and recreate it using kata-qemu as runtime class.
```bash
KUBECONFIG=./kubeconfig-bob kubectl delete pod privileged-without-kata
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/deployments/vulnerable-deployment-kata.yaml
```
Wait for the pod to start, then exec into it:
```bash
KUBECONFIG=./kubeconfig-bob kubectl exec -it privileged-kata -- bash
```
Now check the environment:
```bash
lsblk -l 
# You will **not** see the same disk partiton as before
uname -a
# if you run this command in the minikube VM and in the pod you will see different kernel
```
This confirms that Kata provides VM-level isolation, preventing container breakout even with privileged access.
