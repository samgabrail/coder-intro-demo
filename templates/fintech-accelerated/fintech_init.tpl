#!/bin/bash
set -e

# Initialize home directory
sudo mkdir -p /home/coder
sudo chown -R $(whoami) /home/coder
export HOME=/home/coder
cd $HOME

# Install Python and development tools
sudo apt-get update && sudo apt-get install -y \
    python3-pip \
    python3-venv \
    python3-dev

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install Python packages with specified versions
pip3 install --upgrade pip
pip3 install \
    numpy==1.21.0 \
    pandas==1.3.0 \
    pytest==7.0.0 \
    jupyter==1.0.0 \
    matplotlib==3.4.0 \
    seaborn==0.11.0 \
    requests==2.26.0 \
    python-dotenv==0.19.0

# Clone repository if specified
if [ -n "${repo}" ]; then
    echo "Cloning fintech repository..."
    git clone ${repo} ${localfolder}
    cd ${localfolder}
fi

# Create requirements.txt for version tracking
pip freeze > requirements.txt

# Add Python development aliases
cat << EOF >> ~/.bashrc
# Python development aliases
alias python=python3
alias pip=pip3
alias venv="source .venv/bin/activate"
alias jupyter="jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser"
alias test="pytest"
EOF

# Activate virtual environment by default
echo "source .venv/bin/activate" >> ~/.bashrc
