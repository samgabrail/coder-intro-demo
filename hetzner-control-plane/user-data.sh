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

# Install additional Kubernetes utilities
echo "Installing additional Kubernetes utilities..."
apt-get update -y

# Install git for kubectx
apt-get install -y git fzf jq tmux unzip net-tools

# Install kubectx and kubens
git clone https://github.com/ahmetb/kubectx /opt/kubectx
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Install Homebrew for Linux
echo "Installing Homebrew..."
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Configure Homebrew for root user
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /root/.bashrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# Install k9s using Homebrew
echo "Installing k9s..."
/home/linuxbrew/.linuxbrew/bin/brew install derailed/k9s/k9s

# Add kubectl aliases to root's bashrc
echo "Adding kubectl aliases..."
cat >> /root/.bashrc << 'EOA'
alias k="kubectl"
alias kga="kubectl get all"
alias kgn="kubectl get all --all-namespaces"
alias kdel="kubectl delete"
alias kd="kubectl describe"
alias kg="kubectl get"
EOA

echo "✅ kubectx, kubens, fzf, homebrew, k9s, and kubectl aliases installed successfully"

# Create a basic KIND cluster config file for a single node with proper port mappings
cat > /root/kind-config.yaml <<EOT
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 80
    protocol: TCP
  - containerPort: 30443
    hostPort: 443
    protocol: TCP
EOT

# Create a script to start the KIND cluster and install Coder
cat > /root/install-coder.sh <<EOT
#!/bin/bash
# Exit when any command fails
set -e

# Get the server's public IP address for reference
SERVER_IP=$(curl -s ifconfig.me)

# Extract domains from existing values.yaml
CODER_DOMAIN=$(grep -A 3 'ingress:' k8s-config/values.yaml | grep 'host:' | head -1 | awk '{print $2}' | tr -d '"')
TRAEFIK_DOMAIN="traefik.${CODER_DOMAIN#*.}"

# Create a diagnostic script to check network connectivity
cat > /root/check-network.sh <<EOF
#!/bin/bash
echo "=== Network Diagnostics Tool ==="
echo ""
echo "Testing local ports..."
netstat -tulpn | grep -E ':(80|443|30080|30443)'
echo ""
echo "Testing docker networking..."
docker ps
echo ""
echo "Testing firewall status..."
iptables -L -n
echo ""
echo "Testing services in cluster..."
kubectl get svc -A
echo ""
echo "Testing ingress resources..."
kubectl get ingress -A
echo ""
echo "Testing TLS certificates..."
kubectl get certificates,certificaterequests -A
echo ""
echo "Testing endpoint connectivity..."
curl -v localhost:30080 -o /dev/null
echo ""
echo "Server IP Address: $SERVER_IP"
echo "Coder Domain: $CODER_DOMAIN"
echo ""
EOF
chmod +x /root/check-network.sh

# Check if KIND cluster already exists
if kind get clusters | grep -q "^kind$"; then
  echo "✅ KIND cluster 'kind' already exists, using existing cluster"
else
  echo "🔄 Creating new KIND cluster 'kind'..."
  kind create cluster --config kind-config.yaml
  echo "✅ KIND cluster created successfully"
fi

# Wait for the cluster to be ready
echo "🔄 Ensuring cluster is ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s || true

# Create namespaces (apply is idempotent)
echo "🔄 Creating or ensuring namespaces exist..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: coder
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
EOF

# Install Traefik using Helm
echo "🔄 Installing Traefik..."
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Check if Traefik CRDs exist and install if needed
if ! kubectl get crd ingressroutes.traefik.io > /dev/null 2>&1; then
  echo "🔄 Installing Traefik CRDs..."
  kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
fi

# Create custom values for Traefik to match our KIND port mappings
cat > /root/traefik-values.yaml <<EOF
ingressClass:
  enabled: true
  isDefaultClass: true
ports:
  web:
    port: 8000
    exposedPort: 30080
    protocol: TCP
  websecure:
    port: 8443
    exposedPort: 30443
    protocol: TCP
nodePort:
  web: 30080
  websecure: 30443
service:
  enabled: true
  type: NodePort
persistence:
  enabled: false
dashboard:
  enabled: true
  ingressRoute: true
  middlewares: []
deployment:
  replicas: 1
logs:
  general:
    level: INFO
  access:
    enabled: true
EOF

# Install Traefik with custom values for KIND
echo "🔄 Installing Traefik with NodePort configuration..."
helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    -f /root/traefik-values.yaml \
    --set installCRDs=true

# Wait for Traefik to be ready
echo "🔄 Waiting for Traefik to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=traefik --namespace traefik --timeout=300s || true

# Verify Traefik CRDs are established before proceeding
echo "🔄 Verifying Traefik CRDs..."
MAX_RETRIES=10
COUNT=0
while ! kubectl get crd ingressroutes.traefik.containo.us > /dev/null 2>&1 && [ $COUNT -lt $MAX_RETRIES ]; do
  echo "Waiting for Traefik CRDs to be established ($COUNT/$MAX_RETRIES)..."
  sleep 5
  COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_RETRIES ]; then
  echo "⚠️ Traefik CRDs not detected after maximum retries. Will attempt to install them manually."
  kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
  sleep 5
else
  echo "✅ Traefik CRDs detected successfully"
fi

# Create an ingress route for Traefik dashboard using TLS
echo "🔄 Creating Traefik dashboard IngressRoute with TLS..."
kubectl apply -f - <<EOF
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`$TRAEFIK_DOMAIN`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
  tls:
    certResolver: letsencrypt
EOF

echo "✅ Traefik installed and configured"
echo "  → Configure Traefik dashboard at: https://$TRAEFIK_DOMAIN (after DNS setup)"

# Install cert-manager
echo "🔄 Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --set ingressShim.defaultIssuerName=letsencrypt-prod \
  --set ingressShim.defaultIssuerKind=ClusterIssuer \
  --set ingressShim.defaultIssuerGroup=cert-manager.io

# Wait for cert-manager to be ready
echo "🔄 Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=cert-manager --namespace cert-manager --timeout=300s || true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=webhook --namespace cert-manager --timeout=300s || true

# Create ClusterIssuer for Let's Encrypt (apply is idempotent)
echo "🔄 Creating Let's Encrypt ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: info@tekanaid.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: traefik
EOF

echo "✅ cert-manager installed and configured with Let's Encrypt issuer"

# Install PostgreSQL using Helm
echo "🔄 Installing PostgreSQL..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install PostgreSQL using values file
helm upgrade --install coder-db bitnami/postgresql \
  --namespace coder \
  -f k8s-config/values-postgres.yaml

# Wait for PostgreSQL to be ready
echo "🔄 Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql --namespace coder --timeout=300s || true

# Create a secret with the database URL if it doesn't exist
if ! kubectl get secret coder-db-url -n coder > /dev/null 2>&1; then
  echo "🔄 Creating database URL secret..."
  kubectl create secret generic coder-db-url -n coder --from-literal=url="postgres://coder:coder@coder-db-postgresql.coder.svc.cluster.local:5432/coder?sslmode=disable"
else
  echo "✅ Database URL secret already exists"
fi

# Install Coder with Helm
echo "🔄 Installing Coder..."
helm repo add coder-v2 https://helm.coder.com/v2
helm repo update

# Install Coder with existing values files only
helm upgrade --install coder coder-v2/coder \
  --namespace coder \
  -f k8s-config/secrets.yaml \
  -f k8s-config/values.yaml

# Wait for Coder pod to be ready
echo "🔄 Waiting for Coder to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=coder --namespace coder --timeout=300s || true

# Install the Coder CLI locally for management
echo "🔄 Installing Coder CLI locally..."
kubectl -n coder get secret coder-coder -o jsonpath="{.data.provisionerDaemonKey}" | base64 -d > /root/coder-provisioner-key
cat > /etc/profile.d/coder-cli.sh <<'EOF'
export CODER_URL="http://localhost:8000"
export CODER_SESSION_TOKEN="$(cat /root/coder-provisioner-key 2>/dev/null || echo '')"
EOF
source /etc/profile.d/coder-cli.sh

# Start port forwarding to the Coder instance in the background
kubectl port-forward -n coder svc/coder 8000:80 --address 0.0.0.0 &> /dev/null &
echo $! > /tmp/coder-port-forward.pid

# Wait a bit for the port forwarding to establish
sleep 5

# Check if admin user exists, create if not
echo "🔄 Checking for admin user..."
if ! kubectl -n coder exec -i deployment/coder -- coder users list | grep -q admin; then
  echo "🔄 Creating admin user..."
  # Try with older syntax first
  kubectl -n coder exec -i deployment/coder -- coder users create --username admin --email admin@example.com --password admin123 || \
  # If that fails, try newer syntax without --auth flag
  kubectl -n coder exec -i deployment/coder -- coder users create username=admin email=admin@example.com password=admin123 || \
  echo "⚠️ Admin user creation failed. Please create one manually with: kubectl -n coder exec -i deployment/coder -- coder users create"
else
  echo "✅ Admin user already exists"
fi

# Stop the port forwarding
if [ -f /tmp/coder-port-forward.pid ]; then
  kill $(cat /tmp/coder-port-forward.pid) &> /dev/null || true
  rm /tmp/coder-port-forward.pid
fi

# Check network connectivity to verify everything is working
echo "🔄 Running network diagnostics..."
/root/check-network.sh

echo ""
echo "================================================================"
echo "✨ Coder has been installed! ✨"
echo ""
echo "🛑 IMPORTANT: Configure DNS in Cloudflare 🛑"
echo "  → Point $CODER_DOMAIN to $SERVER_IP"
echo "  → Point $TRAEFIK_DOMAIN to $SERVER_IP"
echo ""  
echo "📊 After DNS setup, access your applications at:"
echo "  → Coder UI: https://$CODER_DOMAIN"  
echo "  → Traefik Dashboard: https://$TRAEFIK_DOMAIN"
echo ""
echo "🔐 Default credentials:"
echo "  → Username: admin"
echo "  → Password: admin123"
echo ""
echo "💡 Cloudflare DNS Configuration Recommendations:"
echo "  1. Create A records pointing to $SERVER_IP"
echo "  2. Initially set Proxy Status to DNS Only (gray cloud) for troubleshooting"
echo "  3. Once working, you can enable 'Proxied' (orange cloud) for added security"
echo "  4. Configure SSL/TLS mode to 'Full' or 'Full (strict)'"
echo ""
echo "🔄 If Let's Encrypt certificate issuance fails:"
echo "  1. Ensure DNS records are properly configured"
echo "  2. Check cert-manager logs: kubectl logs -n cert-manager deployment/cert-manager"
echo "  3. View certificate status: kubectl get certificates,challenges -A"
echo ""
echo "💡 To manage Coder via CLI:"
echo "  1. Connect to your server via SSH"
echo "  2. Run 'kubectl -n coder port-forward svc/coder 8000:80 --address 0.0.0.0 &'"
echo "  3. Export CODER_URL=http://localhost:8000"
echo "  4. Use kubectl to execute Coder commands: kubectl -n coder exec -i deployment/coder -- coder <command>"
echo ""
echo "🔧 If you're still unable to access Coder after DNS setup:"
echo "  1. Run '/root/check-network.sh' to verify network configuration"
echo "  2. Make sure your firewall rules allow traffic on ports 80 and 443"
echo "  3. Check logs with: kubectl logs -n traefik deployment/traefik"
echo "  4. Check certificate status: kubectl get certificates -n coder"
echo ""
echo "🔍 To check cluster status: k9s or kubectl get pods -A"
echo "================================================================"
EOT

# Make the script executable
chmod +x /root/install-coder.sh