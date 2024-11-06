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
    access_modes = ["ReadWriteOnce"]
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
  }
} 