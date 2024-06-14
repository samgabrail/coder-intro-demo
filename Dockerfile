FROM ubuntu:22.04

# Define build arguments for software versions
ARG DOCKER_VERSION=5:24.0.2-1~ubuntu.22.04~jammy
ARG K9S_VERSION=v0.32.0
ARG MINIKUBE_VERSION=latest
ARG KUBECTL_VERSION=v1.25.0
ARG HELM_VERSION=v3.11.2
ARG AWSCLI_VERSION=2.9.1

# Install system dependencies
RUN apt-get update -y && apt-get install -y \
    locales \
    wget unzip python3-pip python3-venv sshpass git openssh-client jq gnupg2 \
    curl sudo apt-transport-https ca-certificates gnupg lsb-release build-essential fzf openjdk-11-jdk \
    htop vim rsync \
    dnsutils net-tools iproute2 telnet tree

# Generate and set locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create a new user named coder and add to sudoers
RUN useradd -m -s /bin/bash coder && \
    echo 'coder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Install Docker
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list and install Docker with retries
RUN apt-get update -y || (sleep 5 && apt-get update -y) || (sleep 5 && apt-get update -y) && \
    apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-compose-plugin && \
    usermod -aG docker coder

# Switch to user coder
USER coder
WORKDIR /home/coder

# Install Homebrew
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/coder/.bashrc && \
    /bin/bash -c "eval \"$($(brew --prefix)/bin/brew shellenv)\""

# Ensure Homebrew is in the PATH and install k9s
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
RUN brew install derailed/k9s/k9s

# Install kubectx and kubens
RUN brew install kubectx

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    sudo install -o coder -g coder -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Install Helm
RUN curl -LO https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz && \
    tar -zxvf helm-${HELM_VERSION}-linux-amd64.tar.gz && \
    sudo mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm-${HELM_VERSION}-linux-amd64.tar.gz

# Install Minikube
RUN curl -LO https://storage.googleapis.com/minikube/releases/$MINIKUBE_VERSION/minikube-linux-amd64 && \
    sudo install minikube-linux-amd64 /usr/local/bin/minikube && \
    rm -f minikube-linux-amd64

# Setup Python virtual environment
RUN python3 -m venv /home/coder/venv
ENV PATH="/home/coder/venv/bin:$PATH"

# Install Python packages in the virtual environment
RUN pip install --upgrade pip cffi && \
    pip install ansible==${ANSIBLE_VERSION} && \
    pip install mitogen ansible-lint jmespath && \
    pip install --upgrade pywinrm

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    sudo ./aws/install && \
    rm -rf awscliv2.zip aws

# Install kube-ps1
RUN brew install kube-ps1

# Set default command
CMD ["/bin/bash"]
