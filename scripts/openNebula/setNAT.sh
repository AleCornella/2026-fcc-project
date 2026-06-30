#!/bin/bash

MINIKUBE_IP=$1
if [[ -z "$MINIKUBE_IP" ]]; then
    echo "Error: No Minikube VM IP provided."
    echo "Usage: ./setNAT.sh <MINIKUBE_VM_IP>"
    exit 1
fi
BRIDGE=$(ip route get "$MINIKUBE_IP" | awk -F"dev " '{print $2}' | awk '{print $1}')
OPEN_NEBULA_IP=$(ip route get 8.8.8.8 | awk -F"src " '{print $2}' | awk '{print $1}')

sudo iptables -t nat -A PREROUTING -d "$OPEN_NEBULA_IP" -p tcp --dport 8080 -j DNAT --to-destination "$MINIKUBE_IP:80"
sudo iptables -I FORWARD -o "$BRIDGE" -d "$MINIKUBE_IP" -p tcp --dport 80 -j ACCEPT
sudo iptables -I FORWARD -i "$BRIDGE" -s "$MINIKUBE_IP" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -d "$MINIKUBE_IP" -p tcp --dport 80 -j MASQUERADE