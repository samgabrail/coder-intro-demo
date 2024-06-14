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