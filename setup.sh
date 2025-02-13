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
  sudo apt install net-tools nload tcpdump dnsutils nmap iptables iperf3 traceroute mtr -y
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

check_and_apply_rule() {
  local rule="$1"
  local table="${2:-filter}" # Default to filter table if not specified

  if ! sudo iptables -t $table -C $rule 2>/dev/null; then
    # Rule does not exist, apply it
    echo "Applying rule to $table table: $rule"
    sudo iptables -t $table -A $rule
  else
    echo "Rule already exists in $table table: $rule"
  fi
}

apply_and_persist_iptables() {
  echo "Applying basic iptables rules for networking security..."
  # List of iptables rules to apply
  # Format: "table rule"
  local rules=(
    "mangle PREROUTING -f -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ALL NONE -j DROP"
    "mangle PREROUTING -p tcp --tcp-flags ALL ALL -j DROP"
    "mangle PREROUTING -m conntrack --ctstate INVALID -j DROP"
    "mangle PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP"
    "mangle PREROUTING -p tcp ! --syn -m state --state NEW -j DROP"
    "mangle PREROUTING -p tcp --syn ! --sport 1024:65535 -j DROP"
    "mangle PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP"
    "raw PREROUTING -p tcp --tcp-flags RST RST -m hashlimit --hashlimit-mode srcip --hashlimit-name rstflood --hashlimit-above 1/s --hashlimit-burst 2 --hashlimit-srcmask 2 -j DROP"
    "raw OUTPUT -p tcp --tcp-flags RST RST -m limit --limit 1/s -j ACCEPT"
    "raw OUTPUT -p tcp --tcp-flags RST RST -j DROP"
    "raw OUTPUT -p icmp -m limit --limit 1/s --limit-burst 2 -j ACCEPT"
    "raw OUTPUT -p icmp -j DROP"
  )

  # Iterate over rules and apply them if they don't already exist
  for rule in "${rules[@]}"; do
    local table=$(echo "$rule" | awk '{print $1}')
    local rule_body=$(echo "$rule" | cut -d' ' -f2-)
    check_and_apply_rule "$rule_body" "$table"
  done

  # Install iptables-persistent to save the rules across reboots
  echo "Checking for iptables-persistent installation..."
  if ! dpkg -l | grep -qw netfilter-persistent; then
    echo "Installing iptables-persistent to save iptables rules across reboots..."
    sudo apt-get install netfilter-persistent -y
  else
    echo "iptables-persistent is already installed."
  fi

  # Save the current iptables rules
  echo "Saving iptables rules..."
  sudo netfilter-persistent save

  echo "iptables rules applied and saved for persistence."
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

if ask_yes_no "Do you want to install network debugging tools?"; then
  install_network_debug_tools
fi

if ask_yes_no "Do you want to install system essentials?"; then
  install_stuff
fi

if ask_yes_no "Do you want to install CrowdSec and some scenarios?"; then
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


if ask_yes_no "Do you want to apply basic iptables rules for networking security and make them persistent?"; then
  apply_and_persist_iptables
fi

echo "Installation complete!"
