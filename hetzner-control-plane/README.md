# Hetzner Cloud KIND Server with Coder

This Terraform configuration creates an Ubuntu 24.04 server on Hetzner Cloud with KIND (Kubernetes IN Docker) pre-installed and configured to run Coder.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (v1.0.0+)
- A Hetzner Cloud account and API token
- SSH key pair for accessing the server and using the file provisioner

## Getting Started

1. Clone this repository:
   ```
   git clone <repository-url>
   cd hetzner-control-plane
   ```

2. Prepare the Coder configuration:
   The k8s-config directory contains configuration files for Coder and PostgreSQL. These files will be copied to the server using Terraform's file provisioner.

3. Create a `terraform.tfvars` file from the example:
   ```
   cp terraform.tfvars.example terraform.tfvars
   ```

4. Edit `terraform.tfvars` and add your Hetzner Cloud API token and other configuration:
   ```
   hcloud_token = "your_hetzner_cloud_api_token"
   server_name = "my-kind-server"
   server_type = "cx31" # Adjust server size if needed
   ssh_private_key_path = "~/.ssh/id_rsa" # Path to your SSH private key for file provisioner
   ```

5. Initialize Terraform:
   ```
   terraform init
   ```

6. Plan the deployment:
   ```
   terraform plan
   ```

7. Apply the configuration:
   ```
   terraform apply
   ```

8. After successful creation, the output will provide the server's IP address and connection instructions.

## Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| `hcloud_token` | Hetzner Cloud API Token (required) | |
| `server_name` | Name of the server | "kind-server" |
| `server_type` | Hetzner server type/size | "cx21" (2 vCPU, 4 GB RAM) |
| `location` | Hetzner datacenter location | "nbg1" (Nuremberg) |
| `ssh_keys` | List of existing SSH key IDs in Hetzner Cloud | [] |
| `ssh_public_key` | SSH public key content for server access | "" |
| `ssh_private_key_path` | Path to SSH private key for provisioners | "" |

## Installed Components

The server includes:
- Docker
- KIND (Kubernetes IN Docker)
- kubectl
- Helm
- Traefik as an ingress controller
- cert-manager with Let's Encrypt integration
- Kubernetes utilities:
  - kubectx & kubens (for easy context and namespace switching)
  - k9s (terminal UI for Kubernetes)
  - fzf (fuzzy finder)
  - Useful kubectl aliases (`k`, `kga`, `kgn`, etc.)

The KIND cluster is configured with:
- A single-node setup with port forwarding (80/443)
- Traefik as the default ingress controller
- cert-manager configured with a ClusterIssuer for Let's Encrypt

## Setting up Coder

Once the server is created:

1. SSH into the server:
   ```
   ssh root@<server-ip>
   ```

2. Run the installation script to create a KIND cluster and install Coder:
   ```
   /root/install-coder.sh
   ```

3. Access Coder:
   - URL: http://server-ip
   - Username: admin
   - Password: admin123

The installation includes:
- A single-node KIND cluster with port forwarding (80/443)
- Traefik as an ingress controller with dashboard
- cert-manager for automatic TLS certificate provisioning
- PostgreSQL database installed via Helm
- Coder installed via Helm

## Configuring DNS for Ingress

For proper ingress functionality with domain names, you need to configure your DNS provider (such as CloudFlare) to point to your Hetzner Cloud server's IP address:

1. Get your server's public IP address from the Terraform output or Hetzner Cloud console.

2. Log in to your CloudFlare account.

3. Add/update DNS records for your domains:
   - Create an A record pointing to your server's IP address
   - For example: `coder.yourdomain.com` → `<server-ip>`
   - For Traefik dashboard: `traefik.yourdomain.com` → `<server-ip>`

4. Configure your Coder Helm values to use these domain names in your ingress configuration.

5. If using CloudFlare, consider:
   - Setting the proxy status to "DNS only" initially for troubleshooting
   - Using "Proxied" status once everything is working for added security and CDN benefits
   - Configuring SSL/TLS settings appropriately (Full or Full (strict) recommended)

## TLS Certificates with Let's Encrypt

The cluster includes cert-manager configured to automatically provision TLS certificates from Let's Encrypt when you create Ingress resources with the appropriate annotations:

1. The `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation is already included in the Coder values.yaml

2. cert-manager will automatically:
   - Request certificates from Let's Encrypt for your domain
   - Validate ownership using HTTP-01 challenges
   - Store the certificates as Kubernetes secrets
   - Renew certificates before they expire

3. Your domain must be publicly accessible for Let's Encrypt validation to work

4. For wildcard certificates, you'll need to use DNS-01 challenges, which require additional configuration specific to your DNS provider

This DNS configuration and certificate setup is essential for your ingress controller to properly route traffic based on hostnames and provide secure HTTPS connections.

## Custom Configuration

The Coder configuration files are located in the `/root/k8s-config` directory:
- `values.yaml`: Main Coder configuration
- `secrets.yaml`: Secret configuration for Coder
- `values-postgres.yaml`: PostgreSQL configuration

You can modify these files in the local k8s-config directory before applying the Terraform configuration to customize your setup.

## File Provisioner

This configuration uses Terraform's file provisioner to copy the k8s-config directory from your local machine to the server. This approach allows you to prepare the configuration files locally and have them automatically transferred to the server.

For the file provisioner to work, you need to:
1. Provide the path to your SSH private key in the `ssh_private_key_path` variable
2. Ensure your SSH public key is either in the Hetzner Cloud console or provided in the `ssh_public_key` variable

## Cleanup

To destroy the infrastructure when no longer needed:
```
terraform destroy
```

This will delete the Hetzner Cloud server and associated resources.

## Notes

- The server uses a local Terraform state file by default.
- The configuration creates a single-node KIND cluster to maximize resource utilization.
- Docker, KIND, kubectl, and Helm are automatically installed via user-data.
- The installation creates a fully functional Coder instance with a default admin user. 