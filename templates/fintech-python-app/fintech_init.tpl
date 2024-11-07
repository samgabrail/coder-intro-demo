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
    echo "Cloning fintech repository..."
    git clone ${repo} ${localfolder}
    cd ${localfolder}
fi

# Install dependencies using pipenv
pipenv install

# Add Python development aliases
cat << EOF >> ~/.bashrc
# Python development aliases
alias python="pipenv run python"
alias pip="pipenv run pip"
alias jupyter="pipenv run jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser"
alias test="pipenv run pytest"
EOF

# Activate pipenv shell by default
echo "pipenv shell" >> ~/.bashrc

# Source the updated bashrc to apply changes
source ~/.bashrc