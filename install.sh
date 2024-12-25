#!/bin/bash

# Variables
INSTALL_DIR="/opt/custom_agent"
ZIP_URL="https://github.com/KPtheitguy/agent/raw/refs/heads/main/projectalphaagent.zip"  # Update with your actual ZIP URL

# Function to check command success
check_success() {
  if [ $? -ne 0 ]; then
    echo "Error: $1 failed. Exiting."
    exit 1
  fi
}

# Step 1: Update the system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt install -y python3 python3-pip unzip nginx osquery
check_success "System update and prerequisites installation"

# Step 2: Create installation directory
echo "Creating installation directory at $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
check_success "Directory creation"

# Step 3: Download and extract the agent package
echo "Downloading and extracting agent package..."
wget -q "$ZIP_URL" -O /tmp/custom_agent.zip
check_success "Downloading agent package"
sudo unzip -q /tmp/custom_agent.zip -d "$INSTALL_DIR"
check_success "Extracting agent package"
sudo rm /tmp/custom_agent.zip

# Step 4: Install Python dependencies
echo "Installing Python dependencies..."
sudo pip3 install -r "$INSTALL_DIR/requirements.txt"
check_success "Python dependencies installation"

# Step 5: Ensure NGINX and osquery are configured
echo "Configuring NGINX and osquery..."
sudo systemctl enable nginx && sudo systemctl start nginx
check_success "NGINX setup"
sudo systemctl enable osqueryd && sudo systemctl start osqueryd
check_success "osquery setup"

# Step 6: Set up the agent as a systemd service
echo "Setting up agent as a systemd service..."
SERVICE_FILE="/etc/systemd/system/custom_agent.service"
sudo bash -c "cat > $SERVICE_FILE" << 'EOF'
[Unit]
Description=Custom Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/custom_agent
ExecStart=/usr/bin/python3 /opt/custom_agent/main.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
check_success "Systemd service creation"

# Step 7: Start the agent service
echo "Starting custom agent service..."
sudo systemctl daemon-reload
sudo systemctl enable custom_agent.service
sudo systemctl start custom_agent.service
check_success "Starting agent service"

echo "Installation complete. The custom agent is running as a service."
