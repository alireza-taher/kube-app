#!/usr/bin/env bash

echo 'Please enter root password in order to stop LoadBalancer and restore original hosts'
sudo -v

# Stop cloud provider kind
sudo pkill -f cloud-provider-kind

# Remove custom entry from /etc/hosts
sudo sed -i.backup "/webapp.local/d" /etc/hosts && sudo rm -f /etc/hosts.backup

# Delete kind cluster
$(go env GOPATH)/bin/kind delete cluster
