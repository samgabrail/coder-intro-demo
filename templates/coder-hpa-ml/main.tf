terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.30.0"
    }
  }
}

data "coder_workspace" "me" {}

data "coder_parameter" "custom_repo_url" {
  name         = "repo"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/3/3f/Git_icon.svg"
  display_name = "Repository URL"
  description  = "Enter a repository URL."
  default      = "https://github.com/samgabrail/fintech-python-template.git"
  mutable      = true
  order        = 1
}

data "coder_parameter" "dotfiles_uri" {
  name         = "dotfiles"
  icon         = "https://raw.githubusercontent.com/jglovier/dotfiles-logo/main/dotfiles-logo-icon.png"
  display_name = "Dotfiles URL"
  default      = "https://github.com/samgabrail/dotfiles"
  description  = "Enter a Dotfiles URL to customize your workspace."
  mutable      = true
  order        = 2
}

data "coder_parameter" "vscode_extensions" {
  name         = "vscode_extensions"
  icon         = "https://raw.githubusercontent.com/dhanishgajjar/vscode-icons/master/png/default.png"
  display_name = "VS Code Extensions"
  default      = jsonencode(["sourcegraph.cody-ai", "ms-python.python", "hashicorp.terraform", "ms-kubernetes-tools.vscode-kubernetes-tools", "ms-toolsai.jupyter"])
  description  = "Enter the VSCode extensions you would like to install in your workspace."
  mutable      = true
  type         = "list(string)"
  order        = 3
}

data "coder_parameter" "vscode_theme" {
  name         = "vscode_theme"
  display_name = "VSCode Color Theme"
  description  = "Enter the VSCode Color theme you would like to install in your workspace."
  default      = "Default Dark Modern"
  icon         = "https://cdn.icon-icons.com/icons2/3053/PNG/512/microsoft_visual_studio_code_alt_macos_bigsur_icon_189955.png"
  mutable      = true
  option {
    name  = "Default Dark Modern"
    value = "Default Dark Modern"
  }
  option {
    name  = "Dracula"
    value = "Dracula"
  }
  option {
    name  = "Solarized Dark"
    value = "Solarized Dark"
  }
  option {
    name  = "Visual Studio Dark"
    value = "Visual Studio Dark"
  }
  option {
    name  = "Default Dark+"
    value = "Default Dark+"
  }
  option {
    name  = "Visual Studio Light"
    value = "Visual Studio Light"
  }
  option {
    name  = "Quiet Light"
    value = "Quiet Light"
  }
  option {
    name  = "Red"
    value = "Red"
  }
  option {
    name  = "Abyss"
    value = "Abyss"
  }
}


resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  startup_script = templatefile("${path.module}/init_script.tpl", {
    repo        = data.coder_parameter.custom_repo_url.value,
    localfolder = local.folder_name,
  dotfiles_uri = data.coder_parameter.dotfiles_uri.value })
  startup_script_behavior = "blocking"
  dir                     = "/home/coder/${local.folder_name}"
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace.me.owner_name, data.coder_workspace.me.owner)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace.me.owner_name, data.coder_workspace.me.owner)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
    GITHUB_TOKEN        = data.coder_external_auth.github.access_token
  }
  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order        = 2
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
    order        = 1
  }
}

# module "vscode-web" {
#   source     = "registry.coder.com/modules/vscode-web/coder"
#   version    = "1.0.14"
#   agent_id   = coder_agent.main.id
#   # install_prefix = "/home/coder/.vscode-web"
#   folder         = "/home/coder/${local.folder_name}"
#   accept_license = true
#   extensions = ["dracula-theme.theme-dracula", "github.copilot", "ms-python.python", "hashicorp.terraform", "ms-kubernetes-tools.vscode-kubernetes-tools"]
#   settings = {
#     "workbench.colorTheme" = "Dracula"
#   }
# }

# module "vscode-web" {
#   source         = "registry.coder.com/modules/vscode-web/coder"
#   version        = "1.0.14"
#   agent_id       = coder_agent.main.id
#   extensions     =["github.copilot@1.195.0", "ms-python.python"]
#   accept_license = true
# }

module "code-server" {
  source         = "registry.coder.com/modules/code-server/coder"
  version        = "1.0.15"
  agent_id       = coder_agent.main.id
  install_prefix = "/home/coder/.vscode-web"
  folder         = "/home/coder/${local.folder_name}"
  extensions     = jsondecode(data.coder_parameter.vscode_extensions.value)
  settings = {
    "workbench.colorTheme" = data.coder_parameter.vscode_theme.value
  }
}

resource "kubernetes_persistent_volume_claim" "workspace" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "coder.owner"                      = data.coder_workspace.me.owner
      "coder.owner_id"                   = data.coder_workspace.me.owner_id
      "coder.workspace_id"               = data.coder_workspace.me.id
      "coder.workspace_name_at_creation" = data.coder_workspace.me.name
    }
  }
  wait_until_bound = false
  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  lifecycle {
    ignore_changes = all
  }
}

data "coder_external_auth" "github" {
  id = "github"
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "ml-workspace"
      "app.kubernetes.io/instance" = data.coder_workspace.me.name
    }
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "ml-workspace"
        "app.kubernetes.io/instance" = data.coder_workspace.me.name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "ml-workspace"
          "app.kubernetes.io/instance" = data.coder_workspace.me.name
        }
      }

      spec {
        security_context {
          fs_group     = 1000 # coder user's group ID
          run_as_user  = 1000 # coder user's ID
          run_as_group = 1000
        }

        container {
          name              = "dev"
          image             = "ghcr.io/coder/envbox:latest"
          image_pull_policy = "Always"
          command           = ["/envbox", "docker"]

          security_context {
            privileged                 = true
            run_as_user                = 1000 # coder user's ID
            run_as_group               = 1000
            allow_privilege_escalation = true
          }

          resources {
            requests = {
              "cpu"    = "${var.min_cpus}"
              "memory" = "${var.min_memory}G"
            }
            limits = {
              "cpu"    = "${var.max_cpus}"
              "memory" = "${var.max_memory}G"
            }
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "CODER_AGENT_URL"
            value = data.coder_workspace.me.access_url
          }
          env {
            name  = "CODER_INNER_IMAGE"
            value = "samgabrail/platformengineering:latest"
          }
          env {
            name  = "CODER_INNER_USERNAME"
            value = "coder"
          }
          env {
            name  = "CODER_BOOTSTRAP_SCRIPT"
            value = coder_agent.main.init_script
          }
          env {
            name  = "CODER_MOUNTS"
            value = "/home/coder:/home/coder"
          }
          env {
            name  = "CODER_ADD_FUSE"
            value = var.create_fuse
          }
          env {
            name  = "CODER_INNER_HOSTNAME"
            value = data.coder_workspace.me.name
          }
          env {
            name  = "CODER_ADD_TUN"
            value = var.create_tun
          }
          env {
            name = "CODER_CPUS"
            value_from {
              resource_field_ref {
                resource = "limits.cpu"
              }
            }
          }
          env {
            name = "CODER_MEMORY"
            value_from {
              resource_field_ref {
                resource = "limits.memory"
              }
            }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
            sub_path   = "home"
          }
          volume_mount {
            mount_path = "/var/lib/coder/docker"
            name       = "home"
            sub_path   = "cache/docker"
          }
          volume_mount {
            mount_path = "/var/lib/coder/containers"
            name       = "home"
            sub_path   = "cache/containers"
          }
          volume_mount {
            mount_path = "/var/lib/sysbox"
            name       = "sysbox"
          }
          volume_mount {
            mount_path = "/var/lib/containers"
            name       = "home"
            sub_path   = "envbox/containers"
          }
          volume_mount {
            mount_path = "/var/lib/docker"
            name       = "docker-storage"
          }
          volume_mount {
            mount_path = "/usr/src"
            name       = "usr-src"
          }
          volume_mount {
            mount_path = "/lib/modules"
            name       = "lib-modules"
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.workspace.metadata.0.name
            read_only  = false
          }
        }
        volume {
          name = "sysbox"
          empty_dir {}
        }
        volume {
          name = "usr-src"
          host_path {
            path = "/usr/src"
            type = ""
          }
        }
        volume {
          name = "lib-modules"
          host_path {
            path = "/lib/modules"
            type = ""
          }
        }
        volume {
          name = "docker-storage"
          empty_dir {}
        }
      }
    }
  }
}

# Add HPA for dynamic scaling
resource "kubernetes_horizontal_pod_autoscaler_v2" "workspace" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}-hpa"
    namespace = var.namespace
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.main[0].metadata[0].name
    }

    min_replicas = 1
    max_replicas = 3

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 90
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 90
        }
      }
    }

    behavior {
      scale_up {
        select_policy                = "Max"
        stabilization_window_seconds = 0
        policy {
          type           = "Pods"
          value          = 4
          period_seconds = 60
        }
      }

      scale_down {
        select_policy                = "Min"
        stabilization_window_seconds = 300
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
    }
  }
}
