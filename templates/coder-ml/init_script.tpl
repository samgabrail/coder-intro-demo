#!/usr/bin/bash
set -e

# Ensure proper permissions for /home/coder
sudo mkdir -p /home/coder
sudo chown -R $(whoami) /home/coder

# Set /home/coder as the standard home directory
export HOME=/home/coder
cd $HOME

# Display current user and directory
whoami
pwd

# Copy default dotfiles if they don't exist
if [ ! -f "/home/coder/.bashrc" ]; then
    cp -rT /etc/skel/. /home/coder/
fi

# Clone the git repository if specified
if [ -z "${repo}" ]; then
    echo "No git repo specified, skipping"
else
    if [ ! -d "${localfolder}" ]; then
        echo "Cloning git repo..."
        git clone ${repo} ${localfolder}
    fi
    cd ${localfolder}
fi

# Check if dotfiles_uri has a value
echo "dotfiles_uri: ${dotfiles_uri}"
if [ -n "${dotfiles_uri}" ]; then
    # Run the coder dotfiles command with the dotfiles_uri
    coder dotfiles -y "${dotfiles_uri}"
else
    echo "dotfiles_uri is not set. Skipping dotfiles setup."
fi

# Now proceed with Python setup
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

# Create Pipfile if it doesn't exist
if [ ! -f "Pipfile" ]; then
    cat << EOF > Pipfile
[[source]]
url = "https://pypi.org/simple"
verify_ssl = true
name = "pypi"

[packages]
notebook = "*"
numpy = "*"
pandas = "*"
scikit-learn = "*"
matplotlib = "*"
psutil = "*"
ipykernel = "*"
jupyter = "*"

[dev-packages]

[requires]
python_version = "3.10"
EOF
fi

# Install dependencies using pipenv with verbose output
pipenv install --verbose

# Install the kernel specifically for this virtual environment
pipenv run python -m ipykernel install --user --name=$(pipenv --venv | xargs basename) --display-name="Python ($(pipenv --venv | xargs basename))"

# Configure VS Code to use the virtual environment
mkdir -p ~/.local/share/code-server/User/
cat << EOF > ~/.local/share/code-server/User/settings.json
{
    "python.defaultInterpreterPath": "$(pipenv --venv)/bin/python",
    "python.terminal.activateEnvironment": true,
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.profiles.linux": {
        "bash": {
            "path": "bash",
            "args": ["--init-file", "$(which pipenv) shell"]
        }
    }
}
EOF

# Create Jupyter config
mkdir -p ~/.jupyter
cat << EOF > ~/.jupyter/jupyter_notebook_config.py
c.NotebookApp.token = ''
c.NotebookApp.password = ''
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.allow_root = True
EOF

# Add Python development aliases and auto-activation to bashrc
cat << EOF >> ~/.bashrc
# Activate virtual environment on login (if terminal is interactive)
if [[ \$- == *i* ]]; then
    pipenv shell
fi

# Start Jupyter notebook
pipenv run jupyter notebook --port=8888 --no-browser &
EOF

# Start Jupyter for the current session
pipenv run jupyter notebook --port=8888 --no-browser >jupyter.log 2>&1 &

