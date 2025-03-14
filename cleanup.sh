#!/usr/bin/env bash

# Stop cloud provider kind
sudo pkill cloud-provider-kind

# Remove custom entry from /etc/hosts
EXTERNAL_IP=$(kubectl get service ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n ingress-nginx)
sudo sed -i.backup "/webapp.local/d" /etc/hosts && sudo rm -f /etc/hosts.backup

# Delete kind cluster
$(go env GOPATH)/bin/kind delete cluster