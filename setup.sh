#!/bin/bash
@echo off

update() {
  apt install sudo -y
  sudo apt update -y
  sudo apt upgrade -y
}

# Function to install network debugging tools
install_network_debug_tools() {
  echo "Installing network debugging tools..."  
  sudo apt install net-tools nload tcpdump nmap iptables traceroute mtr -y
}

# Function to install btop - an interactive system/resource monitor
install_stuff() {
  echo "Installing stuff..."
  sudo apt install neofetch btop zip unzip wget lsb-release tar xz-utils bash-completion gettext-base git curl sudo make g++ rsyslog software-properties-common apt-transport-https ca-certificates gnupg htop screen nano whois snapd build-essential rsync -y
}

install_speedtest() {
  echo "Checking for Speedtest installation..."
  if ! command -v speedtest &> /dev/null; then
    echo "Setting up repositories for Speedtest..."
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
    sudo apt update -y
    echo "Installing Speedtest..."
    sudo apt install speedtest -y
  else
    echo "Speedtest is already installed."
  fi
}

update_crowdsec_scenarios() {
  echo "Updating CrowdSec scenarios..."

  # Fetch the list of scenario names, excluding the header, footer, and "SCENARIOS" line
  local scenarios=$(cscli scenarios list -a | awk 'NF && !/^[- ]*$/{print $1}' | grep -vE '^(Name|SCENARIOS)$')

  # Check if we actually have scenarios to process
  if [ -z "$scenarios" ]; then
    echo "No CrowdSec scenarios found to update."
    return
  fi
  cscli scenarios install $scenarios
  sudo systemctl reload crowdsec*
  echo "All applicable CrowdSec scenarios have been updated."
}

install_crowdsec() {
  echo "Checking for CrowdSec installation..."
  if ! command -v crowdsec &> /dev/null; then
    echo "Setting up repositories for CrowdSec..."
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
    
    echo "Installing CrowdSec, firewall bouncer, and scenarios..."
    sudo apt update
    sudo apt install crowdsec crowdsec-firewall-bouncer-iptables -y
    update_crowdsec_scenarios
    # The script for installing specific scenarios can go here
    if ask_yes_no "Do you want to paste your CrowdSec console enrollment key now?"; then
      echo "Please paste your CrowdSec console enrollment key below:"
      read -r KEY
      cscli console enroll "$KEY"
    else
      echo "Skipping CrowdSec console enrollment."
    fi    
    echo "CrowdSec installed successfully."
  else
    echo "CrowdSec is already installed"
    echo "Updating scenarios"
    update_crowdsec_scenarios
  fi
}

install_docker() {
  echo "Checking for Docker installation..."
  if ! command -v docker &> /dev/null; then    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
  else
    echo "Docker is already installed."
  fi
}

install_nodejs() {
  echo "Checking for Node.js installation..."
  if ! command -v node &> /dev/null; then
    echo "Installing nodejs..."
    echo "Installing nvm (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.profile
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.profile
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.profile

    # Load changes
    source ~/.bashrc
    source ~/.profile

    echo "Installing Node.js..."
    nvm install node
    npm install -g npm@latest
  else
    echo "Node.js is already installed."
  fi
}
install_oh_my_bash() {
  echo "Installing Oh My Bash..."
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
}


# Main script starts here
echo "Updating and upgrading..."
update

echo "This script will install various tools on your Debian system."

# Function to prompt for yes/no with default yes
ask_yes_no() {
  while true; do
    read -p "$1 (Y/n): " answer
    case ${answer:-y} in
        [Yy]* ) return 0;;
        [Nn]* ) return 1;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
  done
}

if ask_yes_no "Do you want to install nload tcpdump nmap iptables traceroute mtr?"; then
  install_network_debug_tools
fi

if ask_yes_no "Do you want to install btop neofetch git curl sudo make unzip wget and more?"; then
  install_stuff
fi

if ask_yes_no "Do you want to install CrowdSec and scenarios?"; then
  install_crowdsec
fi

if ask_yes_no "Do you want to install Node.js?"; then
  install_nodejs
fi

if ask_yes_no "Do you want to install Docker?"; then
  install_docker
fi

if ask_yes_no "Do you want to install Speedtest-cli?"; then
  install_speedtest
fi

if ask_yes_no "Do you want to install Oh My Bash?"; then
  install_oh_my_bash
fi


echo "Installation complete!"
