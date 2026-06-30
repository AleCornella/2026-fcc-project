#!/bin/bash

MINIKUBE_IP=$1
if [[ -z "$MINIKUBE_IP" ]]; then
    echo "Error: No Minikube VM IP provided."
    echo "Usage: ./setNAT.sh <MINIKUBE_VM_IP>"
    exit 1
fi

BRIDGE=$(ip route get "$MINIKUBE_IP" | awk -F"dev " '{print $2}' | awk '{print $1}')
OPEN_NEBULA_IP=$(ip route get 8.8.8.8 | awk -F"src " '{print $2}' | awk '{print $1}')
COMMENT="minikube-nat-rule"

clean_rules() {
    local table=$1
    local chain=$2
    # inverse order otherwise the line numbers will change after each deletion
    local lines=$(sudo iptables -t "$table" -L "$chain" -n --line-numbers | grep "$COMMENT" | awk '{print $1}' | sort -nr)
    
    for line in $lines; do
        sudo iptables -t "$table" -D "$chain" "$line"
    done
}

clean_rules nat PREROUTING
clean_rules filter FORWARD
clean_rules nat POSTROUTING


sudo iptables -t nat -A PREROUTING -d "$OPEN_NEBULA_IP" -p tcp --dport 8080 -m comment --comment "$COMMENT" -j DNAT --to-destination "$MINIKUBE_IP:80"
sudo iptables -I FORWARD -o "$BRIDGE" -d "$MINIKUBE_IP" -p tcp --dport 80 -m comment --comment "$COMMENT" -j ACCEPT
sudo iptables -I FORWARD -i "$BRIDGE" -s "$MINIKUBE_IP" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "$COMMENT" -j ACCEPT
sudo iptables -t nat -A POSTROUTING -d "$MINIKUBE_IP" -p tcp --dport 80 -m comment --comment "$COMMENT" -j MASQUERADE