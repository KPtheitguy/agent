#!/bin/bash

# Variables
INSTALL_DIR="/opt/custom_agent"
VENV_DIR="$INSTALL_DIR/venv"
ZIP_URL="https://github.com/KPtheitguy/agent/raw/refs/heads/main/projectalphaagent.zip"
SERVICE_FILE="/etc/systemd/system/custom_agent.service"
SERVER_URL="https://projectalphaapi.koushik.us/api/v1/agents"

# Auto-provisioning details (can be modified for different environments)
AGENT_NAME="default-agent"
REGISTRATION_TOKEN="default-registration-token"

# Function to clean up in case of failure
cleanup() {
    echo "Cleaning up..."
    sudo systemctl stop custom_agent.service 2>/dev/null || true
    sudo systemctl disable custom_agent.service 2>/dev/null || true
    sudo rm -rf "$INSTALL_DIR"
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    echo "Cleanup complete. Exiting."
    exit 1
}

# Step 1: Test connectivity to the server
echo "Testing connectivity to the server..."
response=$(curl -s -w "%{http_code}" -o /dev/null "$SERVER_URL/ping")
if [[ "$response" != "200" ]]; then
    echo "Error: Unable to connect to the server. Please check the server URL."
    cleanup
fi
echo "Connectivity test passed."

# Step 2: Update the system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt install -y python3 python3-pip python3-venv unzip nginx osquery || cleanup

# Step 3: Create installation directory
echo "Creating installation directory at $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR" || cleanup

# Step 4: Download and extract the agent package
echo "Downloading and extracting agent package..."
wget -q "$ZIP_URL" -O /tmp/custom_agent.zip || cleanup
sudo unzip -o /tmp/custom_agent.zip -d "$INSTALL_DIR" || cleanup
sudo rm /tmp/custom_agent.zip

# Check if requirements.txt exists
if [ ! -f "$INSTALL_DIR/requirements.txt" ]; then
    echo "Error: requirements.txt not found in $INSTALL_DIR. Aborting."
    cleanup
fi

# Step 5: Create and activate a virtual environment
echo "Creating virtual environment..."
python3 -m venv "$VENV_DIR" || cleanup

echo "Installing Python dependencies in virtual environment..."
"$VENV_DIR/bin/pip" install --upgrade pip --break-system-packages || cleanup
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" --break-system-packages || cleanup

# Step 6: Register the agent during installation
echo "Registering the agent with the portal..."
export PYTHONPATH="$INSTALL_DIR"
REGISTRATION_OUTPUT=$("$VENV_DIR/bin/python" -c "
from agent.core.agent_portal import AgentPortal
AgentPortal().register_agent(
    registration_token='$REGISTRATION_TOKEN',
    agent_name='$AGENT_NAME'
)
")

echo "Registration Output:"
echo "$REGISTRATION_OUTPUT"

if [[ "$REGISTRATION_OUTPUT" != *"Agent registered successfully"* ]]; then
    echo "Error: Agent registration failed. See details above. Aborting."
    cleanup
fi

# Step 7: Set up the WebSocket client as a systemd service
echo "Setting up WebSocket client as a systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Custom Agent WebSocket Client
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/agent/communication/websocket_client.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF || cleanup

# Step 8: Start the agent service
echo "Starting custom agent WebSocket client service..."
sudo systemctl daemon-reload || cleanup
sudo systemctl enable custom_agent.service || cleanup
sudo systemctl start custom_agent.service || cleanup

echo "Installation complete. The custom agent WebSocket client is running as a service."
