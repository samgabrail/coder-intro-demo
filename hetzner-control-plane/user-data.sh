#!/bin/bash

# SSH key is handled in the main.tf wrapper

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install KIND
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv ./kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Create a basic KIND cluster config file for a single node
cat > /root/kind-config.yaml <<EOT
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOT

# Create a script to start the KIND cluster and install Coder
cat > /root/install-coder.sh <<EOT
#!/bin/bash
set -e

# Start the KIND cluster
kind create cluster --config kind-config.yaml

# Wait for the cluster to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Create namespaces
kubectl create namespace coder
kubectl create namespace traefik

# Install Traefik using Helm
echo "Installing Traefik..."
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik with custom values for KIND
helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --set ingressClass.enabled=true \
    --set ingressClass.isDefaultClass=true \
    --set ports.web.nodePort=30080 \
    --set ports.websecure.nodePort=30443 \
    --set service.type=NodePort \
    --set persistence.enabled=false \
    --set dashboard.enabled=true \
    --set dashboard.ingressRoute=true

# Wait for Traefik to be ready
echo "Waiting for Traefik to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=traefik --namespace traefik --timeout=300s

# Create an ingress route for Traefik dashboard
cat <<EOF | kubectl apply -f -
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - web
  routes:
    - match: Host(\`traefik.localhost\`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
EOF

echo "Traefik installed and configured"

# Install PostgreSQL using Helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install coder-db bitnami/postgresql \\
    --namespace coder \\
    -f k8s-config/values-postgres.yaml

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql --namespace coder --timeout=300s

# Create a secret with the database URL
kubectl create secret generic coder-db-url -n coder \\
   --from-literal=url="postgres://coder:coder@coder-db-postgresql.coder.svc.cluster.local:5432/coder?sslmode=disable"

# Install Coder with Helm
helm repo add coder-v2 https://helm.coder.com/v2
helm upgrade --install coder coder-v2/coder \\
    --namespace coder \\
    -f k8s-config/secrets.yaml -f k8s-config/values.yaml

# Wait for Coder pod to be ready
echo "Waiting for Coder to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=coder --namespace coder --timeout=300s

# Create an admin user (if Coder is properly configured)
kubectl exec -it deployment/coder -n coder -- coder users create --username admin --email admin@example.com --password admin123 --auth password || echo "Note: Admin user creation failed. You may need to create one manually."

echo ""
echo "================================================================"
echo "Coder has been installed!"
echo ""
echo "Access your applications at:"
echo "- Coder: Access through the ingress configured in your Helm values"  
echo "- Traefik Dashboard: http://traefik.localhost"
echo ""
echo "Username: admin"
echo "Password: admin123"
echo "================================================================"
EOT

# Make the script executable
chmod +x /root/install-coder.sh