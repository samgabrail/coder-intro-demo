terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.5.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.33.2"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "coder" {
}

data "coder_workspace" "me" {
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"
}

resource "coder_app" "code-server" {
  count         = var.code_server ? 1 : 0
  agent_id      = coder_agent.dev.id
  name          = "code-server"
  icon          = "/icon/code.svg"
  url           = "http://localhost:8080"
  relative_path = true
}

# Generate a dummy ssh key that is not accessible so Hetzner cloud does not spam the admin with emails.
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "hcloud_ssh_key" "root" {
  name       = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

resource "hcloud_server" "root" {
  count       = data.coder_workspace.me.start_count
  name        = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  server_type = var.instance_type
  location    = var.instance_location
  image       = var.instance_os
  ssh_keys    = [hcloud_ssh_key.root.id]
  user_data = templatefile("cloud-config.yaml.tftpl", {
    username          = data.coder_workspace.me.owner
    volume_path       = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.root.id}"
    init_script       = base64encode(coder_agent.dev.init_script)
    coder_agent_token = coder_agent.dev.token
    code_server_setup = var.code_server
  })
}

resource "hcloud_volume" "root" {
  name     = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  size     = var.volume_size
  format   = "ext4"
  location = var.instance_location
}

resource "hcloud_volume_attachment" "root" {
  count     = data.coder_workspace.me.start_count
  volume_id = hcloud_volume.root.id
  server_id = hcloud_server.root[count.index].id
  automount = false
}

resource "hcloud_firewall" "root" {
  name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_firewall_attachment" "root_fw_attach" {
  count       = data.coder_workspace.me.start_count
  firewall_id = hcloud_firewall.root.id
  server_ids  = [hcloud_server.root[count.index].id]
}
