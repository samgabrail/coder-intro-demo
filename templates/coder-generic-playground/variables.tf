variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces)"
  default     = "coder"
}

variable "create_tun" {
  type        = bool
  sensitive   = true
  description = "Add a TUN device to the workspace."
  default     = false
}
variable "create_fuse" {
  type        = bool
  description = "Add a FUSE device to the workspace."
  sensitive   = true
  default     = true
}
variable "max_cpus" {
  type        = string
  sensitive   = true
  description = "Max number of CPUs the workspace may use (e.g. 2)."
  default     = "8"
}
variable "min_cpus" {
  type        = string
  sensitive   = true
  description = "Minimum number of CPUs the workspace may use (e.g. .1)."
  default     = "6"
}
variable "max_memory" {
  type        = string
  description = "Maximum amount of memory to allocate the workspace (in GB)."
  sensitive   = true
  default     = "10"
}
variable "min_memory" {
  type        = string
  description = "Minimum amount of memory to allocate the workspace (in GB)."
  sensitive   = true
  default     = "8"
}


locals {
  folder_name = try(element(split("/", data.coder_parameter.custom_repo_url.value), length(split("/", data.coder_parameter.custom_repo_url.value)) - 1), "")
}

