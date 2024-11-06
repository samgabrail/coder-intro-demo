terraform {
  required_providers {
    coder = {
      source = "coder/coder"
      version = "0.22.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.30.0"
    }
  }
}

data "coder_workspace" "me" {}

# Fintech-specific repository parameter
data "coder_parameter" "custom_repo_url" {
  name         = "repo"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/3/3f/Git_icon.svg"
  display_name = "Python Project Template"
  description  = "Fintech Python project template with best practices"
  default      = "https://github.com/samgabrail/fintech-python-template.git"
  mutable      = true
  order        = 1
}

# Pre-configured fintech development extensions
data "coder_parameter" "vscode_extensions" {
  name         = "vscode_extensions"
  display_name = "VS Code Extensions"
  description  = "Pre-configured extensions for fintech development"
  default      = jsonencode([
    "ms-python.python@2024.0.1",            # Python support
    "ms-toolsai.jupyter@2024.2.0",          # Jupyter notebooks
    "redhat.java@1.28.1",                   # Java support
    "vscjava.vscode-spring-boot-dashboard@0.13.1", # Spring Boot
    "golang.go@0.41.0",                     # Go support
    "hashicorp.terraform@2.30.0",           # Infrastructure as Code
    "ms-azuretools.vscode-docker@1.29.0",   # Docker support
    "mtxr.sqltools@0.28.1",                 # SQL tools
    "github.copilot@1.138.0",               # AI assistance
    "dbaeumer.vscode-eslint@2.4.2",         # JavaScript linting
    "zxh404.vscode-proto3@0.5.5",           # Protocol Buffers
    "redhat.vscode-yaml@1.14.0"             # YAML support
  ])
  mutable = true
  type    = "list(string)"
  order   = 2
}

# Add this before the coder_agent resource
data "coder_external_auth" "github" {
  id = "github"
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  
  startup_script = templatefile("${path.module}/fintech_init.tpl", {
    repo         = data.coder_parameter.custom_repo_url.value,
    localfolder  = "fintech-project"
  })
  
  startup_script_behavior = "blocking"
  dir                    = "/home/coder/fintech-project"

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
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
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
    access_modes      = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}


resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
  }
  spec {
    restart_policy = "Never"
    container {
      name              = "dev"
      image             = "ghcr.io/coder/envbox:latest"
      image_pull_policy = "Always"
      command           = ["/envbox", "docker"]
      security_context {
        privileged = true
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
        name       = "home"
        sub_path   = "envbox/docker"
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
    affinity {
      node_affinity {
        required_during_scheduling_ignored_during_execution {
          node_selector_term {
            match_expressions {
              key = "kubernetes.io/hostname"
              operator = "NotIn"
              values = ["k3s-master-1"]
            }
          }
        }
      }
    }
  }
} 