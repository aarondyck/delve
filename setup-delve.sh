#!/bin/bash
# This script interactively sets up the docker-compose.yml file for Delve.

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Default Values ---
CONTAINER_NAME="delve-app"
RESTART_POLICY="unless-stopped"
PUBLISHED_PORT="5001"
PERSISTENT_VOLUME="./data"

# --- Helper Functions ---
prompt_yes_no() {
    local prompt_text="$1"
    local default_answer="$2"
    local response
    
    if [[ "$default_answer" == "Y" ]]; then
        read -p "$(echo -e "${prompt_text} (Y/n) ")" -n 1 -r response
    else
        read -p "$(echo -e "${prompt_text} (y/N) ")" -n 1 -r response
    fi
    echo
    
    # Default to the specified answer if user just presses Enter
    if [[ -z "$response" ]]; then
        response="$default_answer"
    fi

    # Return 0 for 'yes', 1 for 'no'
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- Main Logic ---

# 1. Initial Display
clear
echo -e "${GREEN}--- Delve Docker Compose Setup ---${NC}"
echo
echo "This script will create a 'docker-compose.yml' file with the following default settings:"
echo
echo "  Service Name:      delve"
echo "  Image:             aarondyck/delve:latest"
echo "  Container Name:    ${CONTAINER_NAME}"
echo "  Restart Policy:    ${RESTART_POLICY}"
echo "  Published Port:    ${PUBLISHED_PORT}"
echo "  Persistent Volume: ${PERSISTENT_VOLUME}"
echo

if prompt_yes_no "Are these settings correct?" "Y"; then
    echo -e "${GREEN}[INFO]${NC} Using default settings."
else
    echo -e "\n${GREEN}--- Interactive Configuration ---${NC}"
    
    # --- Container Name ---
    read -p "1. Enter the container name [${CONTAINER_NAME}]: " new_name
    CONTAINER_NAME=${new_name:-$CONTAINER_NAME}

    # --- Restart Policy ---
    echo "2. Select a restart policy:"
    echo "   1) no"
    echo "   2) on-failure"
    echo "   3) always"
    echo "   4) unless-stopped"
    while true; do
        read -p "   Enter your choice [4]: " policy_choice
        policy_choice=${policy_choice:-4}
        case $policy_choice in
            1) RESTART_POLICY="no"; break ;;
            2) RESTART_POLICY="on-failure"; break ;;
            3) RESTART_POLICY="always"; break ;;
            4) RESTART_POLICY="unless-stopped"; break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid selection. Please choose a number from 1 to 4." ;;
        esac
    done

    # --- Published Port ---
    echo "3. Configure the published port:"
    while true; do
        read -p "   Enter the published port [${PUBLISHED_PORT}]: " new_port
        new_port=${new_port:-$PUBLISHED_PORT}
        
        # Check if port is in use
        if ss -tuln | grep -q ":${new_port} "; then
            echo -e "${YELLOW}[WARN]${NC} Port ${new_port} appears to be in use on this system."
            if prompt_yes_no "   Would you like to select a different port?" "Y"; then
                continue # Ask for a new port
            else
                if prompt_yes_no "${RED}[DANGER]${NC} The container may fail to launch. Continue with port ${new_port} anyway?" "N"; then
                    PUBLISHED_PORT=$new_port
                    break # User acknowledged the risk
                else
                    continue # Ask for a new port
                fi
            fi
        else
            PUBLISHED_PORT=$new_port
            break # Port is free
        fi
    done

    # --- Persistent Volume ---
    echo "4. Configure the persistent data folder:"
    while true; do
        read -p "   Enter the path (relative or absolute) [${PERSISTENT_VOLUME}]: " new_volume
        PERSISTENT_VOLUME=${new_volume:-$PERSISTENT_VOLUME}

        if [ ! -d "$PERSISTENT_VOLUME" ]; then
            echo -e "${YELLOW}[WARN]${NC} Folder '${PERSISTENT_VOLUME}' does not exist."
            if prompt_yes_no "   Create this folder structure?" "Y"; then
                mkdir -p "${PERSISTENT_VOLUME}/logs"
                echo -e "${GREEN}[INFO]${NC} Created '${PERSISTENT_VOLUME}/logs'."
                break
            else
                continue # Ask for a new path
            fi
        elif [ -z "$(ls -A "$PERSISTENT_VOLUME")" ]; then
            echo -e "${GREEN}[INFO]${NC} Folder '${PERSISTENT_VOLUME}' exists and is empty."
            if [ ! -d "${PERSISTENT_VOLUME}/logs" ]; then
                 mkdir -p "${PERSISTENT_VOLUME}/logs"
                 echo -e "${GREEN}[INFO]${NC} Created 'logs' subfolder."
            fi
            break
        else
            echo -e "${YELLOW}[WARN]${NC} Folder '${PERSISTENT_VOLUME}' contains existing data."
            echo "   What would you like to do?"
            echo "   1) Change to a different folder"
            echo "   2) Leave the existing data as-is"
            echo "   3) Remove the existing data"
            while true; do
                read -p "   Enter your choice [2]: " data_choice
                data_choice=${data_choice:-2}
                case $data_choice in
                    1) break ;; # Breaks inner loop, will re-prompt for folder path
                    2) 
                        if [ ! -d "${PERSISTENT_VOLUME}/logs" ]; then
                            mkdir -p "${PERSISTENT_VOLUME}/logs"
                            echo -e "${GREEN}[INFO]${NC} Created missing 'logs' subfolder."
                        fi
                        # Use 'break 2' to exit both the inner and outer loops
                        break 2 
                        ;;
                    3)
                        echo -e "${RED}[DANGER]${NC} This will permanently delete all files and folders inside '${PERSISTENT_VOLUME}'."
                        read -p "   To confirm, please type 'yes': " confirmation
                        if [ "$confirmation" == "yes" ]; then
                            rm -rf "${PERSISTENT_VOLUME:?}/"*
                            mkdir -p "${PERSISTENT_VOLUME}/logs"
                            echo -e "${GREEN}[INFO]${NC} Existing data removed and 'logs' subfolder created."
                            break 2
                        else
                            echo -e "${GREEN}[INFO]${NC} Operation cancelled. No data was removed."
                            # Go back to the 3-option choice
                        fi
                        ;;
                    *) echo -e "${RED}[ERROR]${NC} Invalid selection." ;;
                esac
            done
            # If user chose '1', the inner loop breaks and the outer loop continues
            if [ "$data_choice" == "1" ]; then
                continue
            fi
        fi
    done
fi

# 2. Final File Generation
echo
echo -e "${GREEN}[INFO]${NC} Creating 'docker-compose.yml' with the following settings:"
echo "  Container Name:    ${CONTAINER_NAME}"
echo "  Restart Policy:    ${RESTART_POLICY}"
echo "  Published Port:    ${PUBLISHED_PORT}"
echo "  Persistent Volume: ${PERSISTENT_VOLUME}"

cat > docker-compose.yml << EOF
version: '3.8'
services:
  delve:
    image: aarondyck/delve:latest
    container_name: ${CONTAINER_NAME}
    restart: ${RESTART_POLICY}
    ports:
      - "${PUBLISHED_PORT}:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${PERSISTENT_VOLUME}:/data
EOF

echo
echo -e "${GREEN}✅ Success! 'docker-compose.yml' has been created.${NC}"

if prompt_yes_no "Would you like to start the Delve container now?" "Y"; then
    echo -e "${GREEN}[INFO]${NC} Starting Delve... (running 'docker compose up -d')"
    docker compose up -d
    echo -e "${GREEN}✅ Delve is running! You can access it at http://localhost:${PUBLISHED_PORT}${NC}"
else
    echo
    echo "You can start Delve later by running 'docker compose up -d' in this directory."
fi
