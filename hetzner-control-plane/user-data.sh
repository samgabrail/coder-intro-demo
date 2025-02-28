#!/bin/bash

# SSH key is handled in the main.tf wrapper

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg

# Install Docker (still useful for container management)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install K3s with default Traefik
curl -sfL https://get.k3s.io | sh -

# Configure kubectl to use k3s
mkdir -p /root/.kube
ln -sf /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config
export KUBECONFIG=/root/.kube/config
echo "export KUBECONFIG=/root/.kube/config" >> /root/.bashrc

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install additional Kubernetes utilities
echo "Installing additional Kubernetes utilities..."
apt-get update -y

# Install git for kubectx and yq for YAML processing
apt-get install -y git fzf jq tmux unzip net-tools

# Install yq (YAML processor)
echo "Installing yq..."
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

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

# Create a script to install Coder on K3s
cat > /root/install-coder.sh <<EOT
#!/bin/bash
# Exit when any command fails
set -e

# Get the server's public IP address for reference
SERVER_IP=$(curl -s -4 ifconfig.me)
SERVER_IP6=$(curl -s -6 ifconfig.me || echo "")

# Extract domains from existing values.yaml using yq (proper YAML parser)
# Check if values.yaml exists
if [ ! -f k8s-config/values.yaml ]; then
  echo "⚠️ k8s-config/values.yaml not found! Please check the file exists."
  exit 1
fi

# Use yq to extract values
CODER_DOMAIN=$(yq '.coder.ingress.host' k8s-config/values.yaml)
WILDCARD_DOMAIN=$(yq '.coder.ingress.wildcardHost' k8s-config/values.yaml)
TRAEFIK_DOMAIN="traefik.${CODER_DOMAIN#*.}"

# Check if the domains were extracted correctly
if [ "$CODER_DOMAIN" == "null" ] || [ -z "$CODER_DOMAIN" ]; then
  echo "⚠️ Failed to extract Coder domain from values.yaml"
  echo "⚠️ Please check that 'coder.ingress.host' is properly defined in the file"
  exit 1
fi

echo "✨ Using domain: $CODER_DOMAIN ✨"
echo "✨ Using wildcard domain: $WILDCARD_DOMAIN ✨"

# Create a diagnostic script to check network connectivity
cat > /root/check-network.sh <<EOF
#!/bin/bash
echo "=== Network Diagnostics Tool ==="
echo ""
echo "Testing local ports..."
netstat -tulpn | grep -E ':(80|443)'
echo ""
echo "Testing firewall status..."
iptables -L -n
echo ""
echo "Testing K3s traefik setup..."
kubectl get svc -n kube-system traefik -o yaml
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
curl -v -4 localhost:80 -o /dev/null
echo ""
echo "Server IPv4 Address: $SERVER_IP"
if [ ! -z "$SERVER_IP6" ]; then
  echo "Server IPv6 Address: $SERVER_IP6"
fi
echo "Coder Domain: $CODER_DOMAIN"
echo ""
EOF
chmod +x /root/check-network.sh

# Wait for K3s to be ready
echo "🔄 Ensuring K3s cluster is ready..."
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
  name: cert-manager
EOF

# Create traefik dashboard IngressRoute with default K3s traefik
echo "🔄 Creating Traefik dashboard IngressRoute..."
kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: kube-system
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
    certResolver: le
EOF

echo "✅ Traefik dashboard configured"
echo "  → Access Traefik dashboard at: https://$TRAEFIK_DOMAIN (after DNS setup)"

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

# Make sure your values.yaml has proper ingress annotations compatible with K3s Traefik
# Install Coder with existing values files
helm upgrade --install coder coder-v2/coder \
  --namespace coder \
  -f k8s-config/secrets.yaml \
  -f k8s-config/values.yaml



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
if [ ! -z "$SERVER_IP6" ]; then
  echo "  1a. Optionally create AAAA records pointing to $SERVER_IP6"
fi
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
echo "  3. Check logs with: kubectl logs -n kube-system -l app.kubernetes.io/name=traefik"
echo "  4. Check certificate status: kubectl get certificates -n coder"
echo ""
echo "🔍 To check cluster status: k9s or kubectl get pods -A"
echo "================================================================"
EOT

# Make the script executable
chmod +x /root/install-coder.sh