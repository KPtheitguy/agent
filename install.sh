#!/bin/bash

# Variables
INSTALL_DIR="/opt/custom_agent"
ZIP_URL="https://github.com/KPtheitguy/agent/blob/8c538b28b671ba74c63b11316ba814251273a556/projectalphaagent.zip"  

# Function to check command success
check_success() {
  if [ $? -ne 0 ]; then
    echo "Error: $1 failed. Exiting."
    exit 1
  fi
}

# Step 1: Update the system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt install -y python3 python3-pip unzip nginx
check_success "System update and prerequisites installation"

# Step 2: Add osquery repository and install
echo "Adding osquery repository and installing..."
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
check_success "Adding osquery GPG key"
sudo add-apt-repository "deb [arch=amd64] https://pkg.osquery.io/deb deb main"
check_success "Adding osquery repository"
sudo apt update && sudo apt install -y osquery
check_success "Osquery installation"

# Step 3: Create installation directory
echo "Creating installation directory at $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
check_success "Directory creation"

# Step 4: Download and extract the agent package
echo "Downloading and extracting agent package..."
wget -q "$ZIP_URL" -O /tmp/custom_agent.zip
check_success "Downloading agent package"
sudo unzip -q /tmp/custom_agent.zip -d "$INSTALL_DIR"
check_success "Extracting agent package"
sudo rm /tmp/custom_agent.zip

# Step 5: Install Python dependencies
echo "Installing Python dependencies..."
sudo pip3 install -r "$INSTALL_DIR/requirements.txt"
check_success "Python dependencies installation"

# Step 6: Ensure NGINX and osquery are configured
echo "Configuring NGINX and osquery..."
sudo systemctl enable nginx && sudo systemctl start nginx
check_success "NGINX setup"
sudo systemctl enable osqueryd && sudo systemctl start osqueryd
check_success "osquery setup"

# Step 7: Set up the agent as a systemd service
echo "Setting up agent as a systemd service..."
SERVICE_FILE="/etc/systemd/system/custom_agent.service"
sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Custom Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/main.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF"
check_success "Systemd service creation"

# Step 8: Start the agent service
echo "Starting custom agent service..."
sudo systemctl daemon-reload
sudo systemctl enable custom_agent.service
sudo systemctl start custom_agent.service
check_success "Starting agent service"

echo "Installation complete. The custom agent is running as a service."
