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

- A machine running OpenNebul cabable of running:
    - minimum: a VM with 4 cores and 12 GB of RAM
    - raccomended: a VM with 8 cores and 16 GB of RAM
- Locust installed (also on a diffrent machine respcet to the one running OpenNebula)


## Environment Setup
### Locust
On your machine install Locust
```bash
pip install locust
```
### Minikube Virtual Machine
The project was created with OpenNebula running inside a local ubuntu VM using qemu and installed with miniONE. If you don't have a OpenNebula installation ready, you can follow the official instruction at this [link](https://docs.opennebula.io/7.2/getting_started/try_opennebula/opennebula_sandbox_deployment/deploy_opennebula_onprem_with_minione/). Once you have a working installation you can follow the next instructions.

Use this command to copy all the necesary files inside the OpenNebula host.
```bash
./scripts/copy_on_opennebula.sh
```
Now use **ssh** to enter inside your OpenNebula machine.

In order to create the minikube VM run the following command inside the OpenNebula host. The script need to be launched by an user that can interact witht the OpenNebula API (for example the root user or the minione if OpenNebula was isntalled with MiniOne)

The script will auto config some iptables and NAT rules so that you can access the service running on the minikube cluster. It was created to work in a setup where OpenNebula is installed as a QEMU VM on your linux host. It should work even with diffrent setup, but you can use the paramer `--no-nat-config` to avoid changing the iptables rules and use an ssh tunnel to the OpenNeubla VM instead. 
```bash
cd FCC-Project/
(sudo) ./scripts/openNebula/createMinikubeVM.sh
```
You can use the argument `-f` or `--force` to force the script to recreate the templates and images. Pay attantion that this will eliminate:
- all the templates named: `Ubunutu+minikube` and `Minikube_VM`
- all the images named:`minikube-disk`

If for some reason the script isn't working correclty you can manually create the Minikube VM using the Sunstone UI of OpenNubula. Create a VM based on ubuntu 24-04, with a disk 8 core, 16GB of RAM and 50GB of storage and set the cpu to `host-passthrough`. Then if you want to set up iptables and NAT forwarding run `./scripts/openNebula/setNAT.sh [YOUR_MINIKUBE_VM_IP]`.

Once the Minikube Virtual Machine is ready and running, you need to **ssh** in it and then start Minikube using `startMinikube.sh` script:

```bash
./scripts/startMinikube.sh
```
The script will start Minikube and enable Kata container, Calico CNI e the Nginx ingress for the cluster.
It will also create two new user and namespcace that will rappresent two diffrent tenant that share the same cluster.

## Deploy the Workloads
Use this script to deploy the application of Alice (namespace tenant-a). We are using the Google Online Boutique to have a realistic deployment.
```bash
./scripts/deploy-a.sh
```
Afeter around 90s, the time the deplyment is started on the cluster, you can visit `*openNebulaIP*:8080` to see the Google Boutique home page.

You can use `kubectl get pod -n tenant-a` to monitor the starting of the various pods.


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
-  Number of user: 100 (if your VM has 4 core)
-  Rump up: 10
-  Host: http://[OpenNebulaIP]:8080 

## Noisy neighbor
Stop the Locust test if you ran on the previous step.
Now run the job of tenant-b that will esuaste all possible resource.
```bash
./scripts/startStress.sh
```
Wait some second for the job to start and then perfom the same test as before against the boutique of tenant-a.
You can monitor how much CPU is requested by pod on the node using this command: `kubectl describe node | grep -A 5 "Allocated resources:"`.

Now the response time will be much longer. You can notice also by visitong the webiste with your browser.
After 5 minutes the noisy job will end and after little time the website will become faster again.

You can stop the stress test before the 5 minutes using this command: `kubectl delete job cpu-hog -n tenant-b`

## Mitigation
### Implement LimitRange
We now impose a first limitation with LimitRange. 
```bash
kubectl apply -f minikube/limits/tenant-b-limit-range.yaml
```
Now tenant B can no longer create job that take more than 1 entire CPU (before the job take all the avaiable CPU on the node), but we can still esauste all the resources creating multiple jobs.

Before running again the script wait a couple of minutes until the HPA of the tenant A will downscale the deplyment.
```
./scripts/startStress-limited.sh
```
If we start a test with Locust we still have a lost in perfomance.

### Implement ResourceQuota
We now impose a quota of resources for namespace.
```bash
kubectl apply -f minikube/quota/tenant-b-quota.yaml
```
If we rerun the previous stress test `./scripts/startStress-limited.sh` and Locust, you will notice that the response time stays low and similar to the one when no stess tests were conducted. So, we have shown how we can use LimitRange and ResourceQuota to impose a limit and avoid the possible damage created by a noisy neighbor.

# Security Isolation
## Isolation between tenant
To ensure isolation between tenant we can use netowek policy enforced by Calico as the CNI of the cluster.
First we can verify the absence of isolation
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/deployments/deployment-b.yaml
SERVER_IP="$(KUBECONFIG=./kubeconfig-bob kubectl get pod -l app=bob-web-server -o jsonpath='{.items[0].status.podIP}')"
KUBECONFIG=./kubeconfig-alice kubectl apply -f minikube/deployments/pod-a.yaml
KUBECONFIG=./kubeconfig-alice kubectl exec -it pod-client-a -- wget -O - http://$SERVER_IP
```
You should see in the terminal the nginx welcome page, confirming that the two tenant are not isolated by default.
### Network policy
We have prepared two network policies. One is the DenyAll that is applied to both tenant namespace. For tenant A we add a second policy to allow incoming traffic only on the frontend pos, allowing connection to the website.
```bash
KUBECONFIG=./kubeconfig-alice kubectl apply -f minikube/network-policies/tenant-a-policy.yaml
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/network-policies/tenant-b-policy.yaml
```
Now you can't wget the nginx page but you can still visit the boutique of tenat-a.
## Isolation inside pods in a namespace
We insteallled Kata container as a posible runtime. We now will show how using Kata if a pod is compromized, the attacker can't escape the pod as if the pod use the containerd runtime.
First we will deploy a new pod with an ubuntu image and we intentionally set privileged as true to show how much possible data can be exifltrated.
```bash
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/deployments/vulnerable-deployment.yaml
KUBECONFIG=./kubeconfig-bob kubectl exec -it privileged-without-kata -- bash
```
Then mount and verify you can see all he data of the Minikube VM
```bash
lsblk -l
mkdir /host-root
mount /dev/vda1 /host-root
ls -la /host-root
ls -la /host-root/home
```
Now exit, delete the pod, and recreate it using kata-qemu as the runtime class.
```bash
KUBECONFIG=./kubeconfig-bob kubectl delete pod privileged-without-kata
KUBECONFIG=./kubeconfig-bob kubectl apply -f minikube/deployments/vulnerable-deployment-kata.yaml
# wait some second for the pod to be created
KUBECONFIG=./kubeconfig-bob kubectl exec -it privileged-kata -- bash
```
Now you are in a qemu VM. You can verify this by checking the kernel version and see that is different from the one of the Minikube VM and also you will not see the same disk partion of the Minikube VM.
```bash
lsblk -l 
# You will **not** see the same disk partiton as before
uname -a
# if you run this command in the minikube VM and in the pod you will see different kernel
```