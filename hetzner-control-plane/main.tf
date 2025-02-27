terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.43.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
  }
  # Using local state file (default behavior)
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
}

# Generate a new SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload the public key to Hetzner Cloud
resource "hcloud_ssh_key" "generated_key" {
  name       = "${var.server_name}-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

data "hcloud_ssh_key" "existing_key" {
  name = var.ssh_key_name
}

# Create Hetzner Cloud server
resource "hcloud_server" "kind_server" {
  name        = var.server_name
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.generated_key.id, data.hcloud_ssh_key.existing_key.id]

  # Use the external user-data script with a wrapper for SSH key setup
  user_data = file("${path.module}/user-data.sh")

  # Use root user for SSH connection
  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = tls_private_key.ssh_key.private_key_pem
    timeout     = "5m"
  }

  # Wait for cloud-init to complete before proceeding
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Cloud-init finished. Starting provisioning...'",
      "mkdir -p /root/k8s-config"
    ]
  }

  # Copy configuration files
  provisioner "file" {
    source      = "${path.module}/k8s-config/"
    destination = "/root/k8s-config"
  }

  # Verify files and set final permissions
  provisioner "remote-exec" {
    inline = [
      "echo 'Verifying files in /root/k8s-config:'",
      "ls -la /root/k8s-config",
      "chmod -R 600 /root/k8s-config/*.yaml || true",
      "echo 'Setup complete! To start KIND and install Coder, run: /root/install-coder.sh'"
    ]
  }
}
