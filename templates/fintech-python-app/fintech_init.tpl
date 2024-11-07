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

# Create a Pipfile with specified dependencies
cat << EOF > Pipfile
[[source]]
name = "pypi"
url = "https://pypi.org/simple"
verify_ssl = true

[packages]
numpy = ">=1.21.0"
pandas = ">=1.3.0"
pytest = ">=7.0.0"
jupyter = ">=1.0.0"
matplotlib = ">=3.4.0"
seaborn = ">=0.11.0"
requests = ">=2.26.0"
python-dotenv = ">=0.19.0"

[dev-packages]
EOF

# Install dependencies using pipenv
pipenv install

# Clone repository if specified
if [ -n "${repo}" ]; then
    echo "Cloning fintech repository..."
    git clone ${repo} ${localfolder}
    cd ${localfolder}
fi

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
