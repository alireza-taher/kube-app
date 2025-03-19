#!/usr/bin/env bash

set -e

# Install kind
go install sigs.k8s.io/kind@v0.27.0

# Install Cloud Provider Kind (Load Balancer)
go install sigs.k8s.io/cloud-provider-kind@latest

# Setup Kind cluster
$(go env GOPATH)/bin/kind create cluster --config=cluster/kind-config.yaml

# Install resources managed by Kustomize
kubectl apply --server-side --kustomize cluster

# Build Docker image for app
docker build -t alireza/webapp web-app
$(go env GOPATH)/bin/kind load docker-image alireza/webapp:latest

# Wait until the Nginx Ingress is ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Install Helm chart
helm dependency update ./chart
helm upgrade --install web-app ./chart \
     --namespace web-app \
     --create-namespace \
     --wait

echo 'Please enter root password in order to start LoadBalancer and modify hosts'
sudo -v

# Start Cloud Provider Kind
cloud_provider_kind="$(go env GOPATH)/bin/cloud-provider-kind"
sudo bash -c "${cloud_provider_kind} > /dev/null 2>&1 &"

# Wait for the IP to be assigned
echo 'Waiting for external IP to be assigned'
for i in $(seq 1 60);
do
    EXTERNAL_IP=$(kubectl get service ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n ingress-nginx)
    if [ ! -z "${EXTERNAL_IP}" ]
    then
      break
    fi
    sleep 5
done

# Add entry it to /etc/hosts
echo "$EXTERNAL_IP webapp.local" | sudo tee -a /etc/hosts

API_KEY=$(kubectl get secret web-app-secrets -n web-app -o jsonpath="{.data.API_KEY}" | base64 --decode)

echo 'Congratulations! Installation Finished.'
echo 'Web App is accessible at https://webapp.local'
echo "API Key: ${API_KEY}"
echo "Test /calculate endpoint with: curl --insecure -H 'apikey:${API_KEY}' https://webapp.local/calculate?param=10"
