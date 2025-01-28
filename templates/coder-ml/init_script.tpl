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
notebook = ">=7.0.0"
numpy = ">=1.24.0"
pandas = ">=2.0.0"
scikit-learn = ">=1.0.0"
matplotlib = ">=3.7.0"
psutil = ">=5.9.0"
ipykernel = ">=6.0.0"
jupyter = "*"
jupyterlab = "*"

[dev-packages]

[requires]
python_version = "3.10"
EOF
fi

# Install dependencies using pipenv with verbose output and retry on failure
for i in {1..3}; do
    if pipenv install --verbose; then
        break
    fi
    echo "Attempt $i failed. Retrying..."
    sleep 5
done

# Verify package installation
echo "Verifying package installations..."
pipenv run pip list
pipenv run python -c "
import sys
packages = ['numpy', 'pandas', 'sklearn', 'matplotlib', 'psutil']
missing = []
for package in packages:
    try:
        __import__(package)
        print(f'{package} successfully imported')
    except ImportError as e:
        missing.append(package)
        print(f'Error importing {package}: {e}')
if missing:
    print('Missing packages:', missing)
    sys.exit(1)
print('All required packages are installed!')
"

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
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.allow_root = True
c.ServerApp.base_url = '/'
c.ServerApp.allow_origin = '*'
c.ServerApp.disable_check_xsrf = True
c.ServerApp.trust_xheaders = True
EOF

# Add Python development aliases and auto-activation to bashrc
cat << EOF >> ~/.bashrc
# Activate virtual environment on login (if terminal is interactive)
if [[ \$- == *i* ]]; then
    pipenv shell
fi

# Start Jupyter notebook
pipenv run jupyter notebook \
  --no-browser \
  --port=8888 \
  --NotebookApp.allow_origin='*' \
  --NotebookApp.trust_xheaders=True \
  --NotebookApp.disable_check_xsrf=True \
  --NotebookApp.base_url='/' &
EOF

# Start Jupyter for the current session
pipenv run jupyter notebook \
  --no-browser \
  --port=8888 \
  --NotebookApp.allow_origin='*' \
  --NotebookApp.trust_xheaders=True \
  --NotebookApp.disable_check_xsrf=True \
  --NotebookApp.base_url='/' >jupyter.log 2>&1 &

