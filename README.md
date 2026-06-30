# Fog and Cloud Computing Project

This project demonstrates how a **noisy neighbor** can affect the performance of a Kubernetes workload and we can prvide isolation both between tenat and on the same tenant

We deply a minikube cluster inside a VM manged by OpenNebula

## Goal
For the **noisy neighbor** we want to:
- Generate artificial load to simulate a noisy neighbor
- Compare the behavior of the system before and during the stress phase

For the **isolation** we want to:
- create a Calico network policies to block tenant-tenant comunication
- use **Kata** container to isolate the pod

## Repository Layout

- `deployments/` - Kubernetes deployment and job manifests;
- `hpas/` - Horizontal Pod Autoscaler manifests;
- `ingress/` - Ingress resources for the application;
- `scripts/` - Automation scripts for setup, deployment, and stress testing;
- `templates/` - VM and environment templates used to create the lab environment.


## Requirements

- A machine running OpenNebula
- Locust installed (also on a diffrent machine respcet to the one running OpenNebula)


## Environment Setup
### Locust
On your machine install Locust
```bash
pip install locust
```
### Minikube Virtual Machine
In order to create the minikube VM run the following command inside the OpenNebula host. The script need to be launched by an unser that can interact witht the OpenNebula API (for example the root user or the minione if OpenNebula was isntalled with MiniOne)

!!!info  The script will auto config some IP forward and NAT rules so that you can access the service running on the minikube cluster. It created to work in a setup where OpenNebula is installed as QEMU VM on your linux host. If you have a different set up you can use the paramer `--no-nat-config` and use an ssh tunnel to the OpenNeubla VM instead. 
!!!
```bash
.scripts/createMinikubeVM.sh
```

## Start the Kubernetes Cluster

Once the previous script has created the Minikube Virtual Machine you need to ssh in it, then start Minikube using `startMinikube.sh` script:

```bash
.scripts/startMinikube.sh
```
The script will start Minikube and enable Kata container, Calico CNI e the Nginx ingress for the cluster.
It will also create two new user and namespcace that will rappresent two diffrent tenant that share the same cluster.

## Deploy the Workloads
Use this script to deploy the application of Alice (namespace tenant-a). We are using the Google Online Boutique to have a realistic deployment.
```bash
.scripts/deply-a.sh
```
Now if you visit `*openNebulaIP*:8080` you should see the Google Boutique home page.


# Resource Governance
## Normal response time
You can verify the normal response time with Locust.
Start Locust:
```bash
cd python
locust
```
Oen in your browser the locus interface http://127.0.0.1:8089. 
Set:
-  Number of user: 150
-  Rump up: 10
-  Host: *openNebulaIP*:8080 

## Noisy neighbor
Stop the Locust test if you ran on the previous step.
Now run the job of tenant-b that will esuaste all possible resource.
```bash
./scripts/startStress.sh
```
Wait some second for the job to start and then perfom the same test as before against the boutique of tenant-a.
Now the response time will be much longer. You can notice also by visitong the webiste with your browser.
After 5 minutes the noisy job will end and after little time the website will become faster again.

## Mitigation
### Implement LimitRange
We now impose a first limitation with LimitRange. 
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f limits/tenant-b-limit-range.yaml
```
Now we can no longer create job that take all the CPU available, but we can esauste all the resources creating multiple jobs.
```
./scripts/startStress-limited.sh
```
If we start a test with Locust we still have a lost in perfomance.

### Implement ResourceQuota
We now impose a quota of resources for namespace.
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f quota/tenant-b-quota.yaml
```
If we rerun the previous stress test `./scripts/startStress-limited.sh` and Locust, you will notice that the response time stays low and similar to the one when no stess tests were conducted. So, we have shown how we can use LimitRange and ResourceQuota to impose a limit and avoid the possible damage created by a noisy neighbor.

# Security Isolation
## Isolation between tenant
To ensure isolation between tenant we can use netowek policy enforced by Calico as the CNI of the cluster.
First we can verify the absence of isolation
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f deplyments/deployment-b.yaml
SERVER_IP="$(KUBECONFIG=./kubeconfig-bob kubectl get pod -l app=bob-web-server -o jsonpath='{.items[0].status.podIP}')"
KUBECONFIG=./kubeconfig-alice kubectl exec -it emailservice-588bb96b8-5tw56 -- wget -O - http://$SERVER_IP
```
### Network policy
We have prepared two network policies. One is the DenyAll that is applied to both tenant namespace. For tenant-a we add a second policy to allow incoming traffic only on the frontend pos, allowing connection to the website.
```bash
KUBECONFIG=./kubeconfig-alice kubectl apply -f network-policies/tenant-a-policy.yaml
KUBECONFIG=./kubeconfig-bob kubectl apply -f network-policies/tenant-b-policy.yaml
```

## Isolation inside pods in a namespace
We insteallled Kata container as a posible runtime. We now will show how using Kata if a pod is compromized, the attacker can't escape the pod as if the pod use the containerd runtime.
First we will deploy a new pod with an ubuntu image and we intentionally set privileged as true to show how much possible data can be exifltrated.
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f deployment/vulnerable-deployment.yaml
KUBECONFIG=./kubeconfig-bob kubectl exec -it privileged-without-kata -- bash
```
Then mount and see the data of the Minikube VM
```bash
lsblk -l
mkdir /host-root
mount /dev/vda1 /host-root
ls -la /host-root
```
Now delete the pod and recreate it using kata-qemu as the runtime class.
```bash
KUBECONFIG=./kubeconfig-bob kubectl delete pod privileged-without-kata
KUBECONFIG=./kubeconfig-bob kubectl apply -f deployment/vulnerable-deployment-kata.yaml
```
Now you are in a qemu VM. You can verify this by checking the kernel version and see that is different from the one of the Minikube VM and also you will not see the same disk partion of the Minikube VM.
```bash
KUBECONFIG=./kubeconfig-bob kubectl delete pod privileged-without-kata
KUBECONFIG=./kubeconfig-bob kubectl apply -f deployment/vulnerable-deployment-kata.yaml
KUBECONFIG=./kubeconfig-bob kubectl exec -it privileged-kata -- bash
```
```bash
lsblk -l 
# You will **not** see the same disk partiton as before
uname -a
# if you run this command in the minikube VM and in the pod you will see different kernel
```