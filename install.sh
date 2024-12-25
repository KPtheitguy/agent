#!/bin/bash

# Variables
INSTALL_DIR="/opt/custom_agent"
VENV_DIR="$INSTALL_DIR/venv"
ZIP_URL="https://github.com/KPtheitguy/agent/raw/refs/heads/main/projectalphaagent.zip"
SERVICE_FILE="/etc/systemd/system/custom_agent.service"

# Prompt for registration details
read -p "Enter Agent Name: " AGENT_NAME
read -p "Enter Registration Token: " REGISTRATION_TOKEN
read -p "Enter Site Name: " SITE_NAME
read -p "Enter Location: " LOCATION

# Step 1: Update the system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt install -y python3 python3-pip python3-venv unzip nginx osquery
check_success "System update and prerequisites installation"

# Step 2: Create installation directory
echo "Creating installation directory at $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
check_success "Directory creation"

# Step 3: Download and extract the agent package
echo "Downloading and extracting agent package..."
wget -q "$ZIP_URL" -O /tmp/custom_agent.zip
check_success "Downloading agent package"
sudo unzip -o /tmp/custom_agent.zip -d "$INSTALL_DIR"
check_success "Extracting agent package"
sudo rm /tmp/custom_agent.zip

# Step 4: Create and activate a virtual environment
echo "Creating virtual environment..."
python3 -m venv "$VENV_DIR"
check_success "Virtual environment creation"

echo "Installing Python dependencies in virtual environment..."
"$VENV_DIR/bin/pip" install --upgrade pip --break-system-packages
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" --break-system-packages
check_success "Python dependencies installation"

# Step 5: Set up the agent as a systemd service
echo "Setting up agent as a systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Custom Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/main.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
check_success "Systemd service creation"

# Step 6: Start the agent service
echo "Starting custom agent service..."
sudo systemctl daemon-reload
sudo systemctl enable custom_agent.service
sudo systemctl start custom_agent.service
check_success "Starting agent service"

echo "Installation complete. The custom agent is running as a service."
