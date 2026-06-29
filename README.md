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
.script/deply-a.sh
```
Now if you visit `*openNebulaIP*:8080` you should see the Google Boutique home page.


# Noisy Neighbor Evaluation
## Normal response time
You can verify the normal response time with Locust.
Start Locust:
```
cd python
locust
```
Oen in your browser the locus interface http://127.0.0.1:8089. 
Set:
-  .... *openNebulaIP*:8080 
-  ..... 150
-  ....... dsad

## Noisy neighbor
Stop the Locust ... if you ran on the previous step.
Now run the job of tenant-b that will esuaste all possible resource.
```
./script startStress.sh
```
Wait some second for the job to start and then perfom the same test as before against the boutique of tenant-a.
Now the response time will be much longer. You can notice also by visitong the webiste with your browser.
After 5 minutes the noisy job will end and after little time the website will becme faster again.

## Implement ResourceQuota and etc...
