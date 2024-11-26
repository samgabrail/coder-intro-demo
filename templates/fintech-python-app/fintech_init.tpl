#!/bin/bash
set -e

# Initialize home directory
sudo mkdir -p /home/coder
sudo chown -R $(whoami) /home/coder
export HOME=/home/coder
cd $HOME

# Clean up apt cache before installing
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Install Python and development tools with required build dependencies
sudo apt-get update && sudo apt-get install -y \
    python3-pip \
    python3-dev \
    build-essential \
    gcc \
    g++ \
    gfortran \
    libopenblas-dev \
    liblapack-dev \
    pkg-config

# Install pipenv
pip3 install --user pipenv

# Add pipenv to PATH and persist it
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Clone repository if specified
if [ -n "${repo}" ]; then
    if [ ! -d "${localfolder}" ]; then
        echo "Cloning fintech repository..."
        git clone ${repo} ${localfolder}
    else
        echo "Directory ${localfolder} already exists, skipping clone"
    fi
    cd ${localfolder}
fi

# Install dependencies using pipenv (without shell activation)
pipenv install

# Add Python development aliases to bashrc
cat << EOF >> ~/.bashrc
# Activate virtual environment on login (if terminal is interactive)
if [[ \$- == *i* ]]; then
    pipenv shell
fi
EOF