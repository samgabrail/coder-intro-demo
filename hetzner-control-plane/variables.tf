# Define variables
variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Name of the server"
  type        = string
  default     = "kind-server"
}

variable "server_type" {
  description = "Server type/size"
  type        = string
  default     = "cx21" # 2 vCPU, 4 GB RAM
}

variable "location" {
  description = "Server location"
  type        = string
  default     = "nbg1" # Nuremberg
}

variable "ssh_key_name" {
  description = "Name of the existing SSH key in Hetzner Cloud"
  type        = string
  default     = "SamDesktop"
}
