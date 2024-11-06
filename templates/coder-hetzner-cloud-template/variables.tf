variable "hcloud_token" {
  description = <<EOF
Coder requires a Hetzner Cloud token to provision workspaces.
EOF
  sensitive   = true
  validation {
    condition     = length(var.hcloud_token) == 64
    error_message = "Please provide a valid Hetzner Cloud API token."
  }
}

variable "instance_location" {
  description = "What region should your workspace live in?"
  default     = "nbg1"
  validation {
    condition     = contains(["nbg1", "fsn1", "hel1"], var.instance_location)
    error_message = "Invalid zone!"
  }
}

variable "instance_type" {
  description = "What instance type should your workspace use?"
  default     = "cx41"
  validation {
    condition     = contains(["cx11", "cx21", "cx31", "cx41", "cx51"], var.instance_type)
    error_message = "Invalid instance type!"
  }
}

variable "instance_os" {
  description = "Which operating system should your workspace use?"
  default     = "ubuntu-22.04"
  validation {
    condition     = contains(["ubuntu-22.04", "ubuntu-20.04", "ubuntu-18.04", "debian-11", "debian-10"], var.instance_os)
    error_message = "Invalid OS!"
  }
}

variable "volume_size" {
  description = "How much storage space do you need in GB (can't be less then 10)?"
  default     = "10"
  validation {
    condition     = var.volume_size >= 10
    error_message = "Invalid volume size!"
  }
}

variable "code_server" {
  description = "Should Code Server be installed?"
  default     = "true"
  validation {
    condition     = contains(["true", "false"], var.code_server)
    error_message = "Your answer can only be yes or no!"
  }
}
