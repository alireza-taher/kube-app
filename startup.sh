#!/usr/bin/env bash

set -e

# Install kind
go install sigs.k8s.io/kind@v0.27.0

# Install Cloud Provider Kind (Load Balancer)
go install sigs.k8s.io/cloud-provider-kind@latest

# Setup Kind cluster
$(go env GOPATH)/bin/kind create cluster --config=cluster/kind-config.yaml

# Install Kubernetes Metrics server (for auto-scaling)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Path Metrics server to skip ssl verification
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[{"op": "add",
        "path": "/spec/template/spec/containers/0/args/-",
        "value": "--kubelet-insecure-tls"}]'

# Install Nginx Ingress Controller
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml

# Wait until Ingress is installed and ready
echo "Waiting for Nginx Ingress Controller to be ready"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Patch the ingress-nginx-controller Deployment to enable Prometheus metrics
kubectl patch service ingress-nginx-controller \
  -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add",
        "path": "/spec/ports/-",
        "value": {"name": "prometheus", "port": 10254, "targetPort": "prometheus"}}]'
kubectl patch deployment ingress-nginx-controller \
  -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add",
          "path": "/spec/template/spec/containers/0/args/-",
          "value": "--enable-metrics"},
        {"op": "add",
          "path": "/spec/template/spec/containers/0/ports/-",
          "value": {"containerPort": 10254, "name": "prometheus"}}]'
kubectl patch deployment ingress-nginx-controller \
  -n ingress-nginx \
  --type='merge' \
  -p='{"spec": {"template": {"metadata": {
        "annotations": {
          "prometheus.io/scrape": "true",
          "prometheus.io/port": "10254"
        }
      }}}}'

# Sleep for 5 seconds for kubernetes to pickup the patches and trigger a new deployment
sleep 5

# Wait until the patches are applied
echo "Waiting for metrics server to be enabled on Nginx Ingress Controller"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Build Docker image for app
docker build -t alireza/webapp web-app
$(go env GOPATH)/bin/kind load docker-image alireza/webapp:latest

# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.crds.yaml

# Install Helm chart
helm dependency update ./chart
helm upgrade --install web-app ./chart \
     --namespace web-app \
     --create-namespace \
     --wait

echo 'Please enter root password in order to start kind cloud provider (LoadBalancer)'
sudo -v

# Start Cloud Provider Kind
sudo bash -c '$(go env GOPATH)/bin/cloud-provider-kind > /dev/null 2>&1 &'

# Wait for the IP to be assigned
echo 'Waiting for external IP to be assigned'
for i in $(seq 1 60);
do
    [[ ! -z $(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]] && break
    sleep 5
done

# Get Ingress IP and add it to /etc/hosts
EXTERNAL_IP=$(kubectl get service ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n ingress-nginx)
echo "$EXTERNAL_IP webapp.local" | sudo tee -a /etc/hosts

API_KEY=$(kubectl get secret web-app-secrets -n web-app -o jsonpath="{.data.API_KEY}" | base64 --decode)

echo 'Congratulations! Installation Finished.'
echo 'Web App is accessible at https://webapp.local'
echo "API Key: ${API_KEY}"
echo "Test /calculate endpoint with: curl --insecure -H 'apikey:${API_KEY}' https://webapp.local/calculate?param=10"