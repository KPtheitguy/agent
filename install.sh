#!/bin/bash

# Variables
INSTALL_DIR="/opt/custom_agent"
VENV_DIR="$INSTALL_DIR/venv"
ZIP_URL="https://github.com/KPtheitguy/agent/raw/refs/heads/main/projectalphaagent.zip"
SERVICE_FILE="/etc/systemd/system/custom_agent.service"
LOG_FILE="/var/log/custom_agent_install.log"

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

# Prompt for registration details
read -p "Enter Agent Name: " AGENT_NAME
read -p "Enter Registration Token: " REGISTRATION_TOKEN

# Step 1: Update the system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt install -y python3 python3-pip python3-venv unzip curl || cleanup

# Step 2: Install osquery
echo "Adding osquery repository and installing..."
if curl -fsSL https://pkg.osquery.io/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/osquery-keyring.gpg; then
    echo "deb [signed-by=/usr/share/keyrings/osquery-keyring.gpg] https://pkg.osquery.io/deb deb main" | sudo tee /etc/apt/sources.list.d/osquery.list
    sudo apt-get update && sudo apt-get install -y osquery || cleanup
else
    echo "Failed to add osquery repository. Attempting standalone package installation..."
    OSQUERY_DEB="osquery-5.11.2.linux.x86_64.deb"
    OSQUERY_DEB_URL="https://github.com/osquery/osquery/releases/download/5.11.2/$OSQUERY_DEB"
    wget -q "$OSQUERY_DEB_URL" -O /tmp/$OSQUERY_DEB || cleanup
    sudo dpkg -i /tmp/$OSQUERY_DEB || cleanup
    sudo apt-get -f install -y || cleanup
    sudo rm /tmp/$OSQUERY_DEB
fi

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
"$VENV_DIR/bin/pip" install --upgrade pip || cleanup
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" || cleanup

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

# Step 7: Test WebSocket connectivity
echo "Testing WebSocket connectivity to the server..."
WEBSOCKET_TEST_OUTPUT=$("$VENV_DIR/bin/python" -c "
from agent.core.websocket_client import WebSocketClient
import asyncio
agent_id = '$AGENT_NAME'  # Replace with proper logic to retrieve agent ID
client = WebSocketClient(agent_id)
result = asyncio.run(client.test_connection())
print('WebSocket test result:', result)
")
echo "$WEBSOCKET_TEST_OUTPUT"
if [[ "$WEBSOCKET_TEST_OUTPUT" != *"Successfully connected"* ]]; then
    echo "Error: WebSocket connection test failed. Aborting installation."
    cleanup
fi

# Step 8: Set up the agent as a systemd service
echo "Setting up agent as a systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
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
EOF || cleanup

# Step 9: Start the agent service
echo "Starting custom agent service..."
sudo systemctl daemon-reload || cleanup
sudo systemctl enable custom_agent.service || cleanup
sudo systemctl start custom_agent.service || cleanup

echo "Installation complete. The custom agent is running as a service."
