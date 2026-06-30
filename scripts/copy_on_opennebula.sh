#!/bin/bash
echo "Use scp to copy all the file from host to the OpenNebula VM."
echo "Insert the username of the OpenNebula VM:"
read username
echo "Insert the IP of the OpenNebula VM:"
read ip

ssh "$username@$ip "mkdir -p ~/FCC-Project"
scp -r ./minikube "$username@$ip:~/FCC-Project/minikube"
scp -r ./scripts "$username@$ip:~/FCC-Project/scripts"
scp -r ./templates "$username@$ip:~/FCC-Project/templates"