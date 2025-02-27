# Output IP address
output "server_ip" {
  value = hcloud_server.kind_server.ipv4_address
}

output "server_status" {
  value = hcloud_server.kind_server.status
}

# Output the private key
output "private_key" {
  value     = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}

# Output SSH connection command
output "ssh_command" {
  value = "ssh -i private_key.pem root@${hcloud_server.kind_server.ipv4_address}"
}

output "instructions" {
  value = <<-EOT
    Server has been created with IP: ${hcloud_server.kind_server.ipv4_address}
    
    * IMPORTANT: Save your SSH private key to a file *
    
    Run the following command to save the private key:
    terraform output -raw private_key > private_key.pem
    
    Then set the correct permissions:
    chmod 600 private_key.pem
    
    To connect via SSH you can either use this command:
    ssh -i private_key.pem root@${hcloud_server.kind_server.ipv4_address}
    
    or use the following command to connect as with the SamDesktop ssh key name:
    ssh root@${hcloud_server.kind_server.ipv4_address}
    
    Once connected, you can:
    1. Create a KIND cluster and install Coder with:
       ./install-coder.sh
    
    2. Access Coder at:
       http://${hcloud_server.kind_server.ipv4_address}
       Username: admin
       Password: admin123
  EOT
}
