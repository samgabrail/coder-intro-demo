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
