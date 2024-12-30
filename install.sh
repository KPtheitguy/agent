#!/bin/bash

# Variables
INSTALL_DIR="/opt/custom_agent"
VENV_DIR="$INSTALL_DIR/venv"
ZIP_URL="https://github.com/KPtheitguy/agent/raw/refs/heads/main/projectalphaagent.zip"
SERVICE_FILE="/etc/systemd/system/custom_agent.service"
OSQUERY_REPO_URL="https://pkg.osquery.io/deb"
LOG_FILE="/var/log/custom_agent_install.log"

# Function to clean up in case of failure
cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
    sudo systemctl stop custom_agent.service 2>/dev/null || true
    sudo systemctl disable custom_agent.service 2>/dev/null || true
    sudo rm -rf "$INSTALL_DIR"
    sudo rm -f "$SERVICE_FILE"
    sudo rm -f /etc/apt/sources.list.d/osquery.list
    sudo rm -f /etc/apt/keyrings/osquery-archive-keyring.gpg
    sudo systemctl daemon-reload
    echo "Cleanup complete. Exiting." | tee -a "$LOG_FILE"
    exit 1
}

# Prompt for registration details
read -p "Enter Agent Name: " AGENT_NAME
read -p "Enter Registration Token: " REGISTRATION_TOKEN

# Step 1: Update the system and install prerequisites
echo "Updating system and installing prerequisites..." | tee -a "$LOG_FILE"
sudo apt update && sudo apt install -y python3 python3-pip python3-venv unzip nginx curl || cleanup

# Step 2: Add osquery repository and install
echo "Adding osquery repository and installing..." | tee -a "$LOG_FILE"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkg.osquery.io/gpg.key | gpg --dearmor -o /etc/apt/keyrings/osquery-archive-keyring.gpg || cleanup
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/osquery-archive-keyring.gpg] $OSQUERY_REPO_URL deb main" | sudo tee /etc/apt/sources.list.d/osquery.list > /dev/null || cleanup
sudo apt update || cleanup
sudo apt install -y osquery || cleanup

# Step 3: Create installation directory
echo "Creating installation directory at $INSTALL_DIR..." | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR" || cleanup

# Step 4: Download and extract the agent package
echo "Downloading and extracting agent package..." | tee -a "$LOG_FILE"
wget -q "$ZIP_URL" -O /tmp/custom_agent.zip || cleanup
sudo unzip -o /tmp/custom_agent.zip -d "$INSTALL_DIR" || cleanup
sudo rm /tmp/custom_agent.zip

# Step 5: Check if requirements.txt exists
if [ ! -f "$INSTALL_DIR/requirements.txt" ]; then
    echo "Error: requirements.txt not found in $INSTALL_DIR. Aborting." | tee -a "$LOG_FILE"
    cleanup
fi

# Step 6: Create and activate a virtual environment
echo "Creating virtual environment..." | tee -a "$LOG_FILE"
python3 -m venv "$VENV_DIR" || cleanup

echo "Installing Python dependencies in virtual environment..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install --upgrade pip || cleanup
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" || cleanup

# Step 7: Register the agent during installation
echo "Registering the agent with the portal..." | tee -a "$LOG_FILE"
export PYTHONPATH="$INSTALL_DIR"
REGISTRATION_OUTPUT=$("$VENV_DIR/bin/python" -c "
from agent.core.agent_portal import AgentPortal
AgentPortal().register_agent(
    registration_token='$REGISTRATION_TOKEN',
    agent_name='$AGENT_NAME'
)
")
if [[ "$REGISTRATION_OUTPUT" != *"Agent registered successfully"* ]]; then
    echo "Error: Agent registration failed. Aborting." | tee -a "$LOG_FILE"
    cleanup
fi

# Step 8: Test WebSocket connectivity
echo "Testing WebSocket connectivity to the server..." | tee -a "$LOG_FILE"
WEBSOCKET_TEST=$("$VENV_DIR/bin/python" -c "
from agent.core.websocket_client import WebSocketClient
client = WebSocketClient('$AGENT_NAME')
import asyncio
result = asyncio.run(client.test_connection())
print('Success' if result else 'Failure')
")
if [[ "$WEBSOCKET_TEST" != "Success" ]]; then
    echo "Error: WebSocket connection test failed. Aborting installation." | tee -a "$LOG_FILE"
    cleanup
fi

# Step 9: Set up the agent as a systemd service
echo "Setting up agent as a systemd service..." | tee -a "$LOG_FILE"
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

# Step 10: Start the agent service
echo "Starting custom agent service..." | tee -a "$LOG_FILE"
sudo systemctl daemon-reload || cleanup
sudo systemctl enable custom_agent.service || cleanup
sudo systemctl start custom_agent.service || cleanup

echo "Installation complete. The custom agent is running as a service." | tee -a "$LOG_FILE"
