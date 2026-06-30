#!/bin/bash
echo "Use scp to copy all the file from host to the OpenNebula VM."
echo "Inserert the usrname of the OpenNebula VM:"
read username
echo "Insert the IP of the OpenNebula VM:"
read ip

scp -r ./ "$username@$ip:~/FCC-Project"
