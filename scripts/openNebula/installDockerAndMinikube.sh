#!/bin/bash

sudo apt-get update
sudo apt-get upgrade -y

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
    

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo systemctl start docker
sudo groupadd docker
sudo usermod -aG docker minikube
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo apt-get install -y nginx libnginx-mod-stream
sudo adduser minikube libvirt
sudo adduser minikube kvm
sudo tee /etc/nginx/nginx.conf <<EOF
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    # multi_accept on;
}

stream {
    server {
        listen 80; 
        
        proxy_pass 192.168.49.2:80;
    }
}
EOF
sudo systemctl restart nginx

echo "2. Install MiniKube"
cd  /home/minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
sudo dpkg -i minikube_latest_amd64.deb
# echo 'alias kubectl="minikube kubectl --"' >> /home/minikube/.bashrc
# minikube kubectl options
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chown minikube kubectl
su - minikube -c "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chown minikube get_helm.sh
chmod 700 get_helm.sh
su - minikube -c "./get_helm.sh"
sleep 5