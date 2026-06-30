#!/bin/bash
# take the minikube vm ip and bridge as parameters
MINIKUBE_IP=$1
BRIDGE="minionebr"
OPEN_NEBULA_IP=$(hostname -I | awk '{print $1}')

sudo nft add rule ip nat PREROUTING ip daddr "$OPEN_NEBULA_IP" tcp dport 8080 dnat to 172.16.100.2:80

sudo nft insert rule ip filter FORWARD oifname "$BRIDGE" ip daddr "$MINIKUBE_IP" tcp dport 80 accept
sudo nft insert rule ip filter FORWARD iifname "$BRIDGE" ip saddr "$MINIKUBE_IP" ct state established,related accept
sudo nft add rule ip nat POSTROUTING ip daddr "$MINIKUBE_IP" tcp dport 80 masquerade

# don't save rule (in case of error just reboot the machine to clear the rules)
# sudo nft list ruleset > /etc/nftables.conf
# systemctl enable nftables