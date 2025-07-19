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
# Get the current user's ID to use as a sensible default.
PUID=$(id -u)
PGID=$(id -g)

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
    
    if [[ -z "$response" ]]; then
        response="$default_answer"
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

handle_persistent_volume() {
    echo -e "\n${GREEN}--- Validating Persistent Data Folder ---${NC}"
    while true; do
        if [ "$INTERACTIVE_MODE" = true ]; then
            read -p "Enter the path for the persistent data folder [${PERSISTENT_VOLUME}]: " new_volume
            PERSISTENT_VOLUME=${new_volume:-$PERSISTENT_VOLUME}
        fi

        if [ ! -d "$PERSISTENT_VOLUME" ]; then
            echo -e "${YELLOW}[WARN]${NC} Folder '${PERSISTENT_VOLUME}' does not exist."
            if prompt_yes_no "Create this folder structure?" "Y"; then
                mkdir -p "${PERSISTENT_VOLUME}/logs"
                echo -e "${GREEN}[INFO]${NC} Created '${PERSISTENT_VOLUME}/logs'."
                break
            else
                [ "$INTERACTIVE_MODE" = true ] && continue || exit 1
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
            echo "   1) Change folder  2) Leave data as-is  3) Remove existing data"
            while true; do
                read -p "   Enter your choice [2]: " data_choice; data_choice=${data_choice:-2}
                case $data_choice in
                    1) INTERACTIVE_MODE=true; break ;;
                    2) 
                        if [ ! -d "${PERSISTENT_VOLUME}/logs" ]; then
                            mkdir -p "${PERSISTENT_VOLUME}/logs"
                            echo -e "${GREEN}[INFO]${NC} Created missing 'logs' subfolder."
                        fi
                        return 0 ;;
                    3)
                        echo -e "${RED}[DANGER]${NC} This will attempt to remove all files and folders inside '${PERSISTENT_VOLUME}'."
                        read -p "   To confirm, please type 'yes': " confirmation
                        if [ "$confirmation" == "yes" ]; then
                            rm -rf "${PERSISTENT_VOLUME:?}/"*
                            mkdir -p "${PERSISTENT_VOLUME}/logs"
                            echo -e "${GREEN}[INFO]${NC} 'logs' subfolder created."
                            return 0
                        else
                            echo -e "${GREEN}[INFO]${NC} Operation cancelled. No data was removed."
                        fi ;;
                    *) echo -e "${RED}[ERROR]${NC} Invalid selection." ;;
                esac
            done
            if [ "$data_choice" == "1" ]; then continue; fi
        fi
    done
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
echo "  User ID (PUID):    ${PUID}"
echo "  Group ID (PGID):   ${PGID}"
echo

INTERACTIVE_MODE=false
if prompt_yes_no "Are these settings correct?" "Y"; then
    echo -e "${GREEN}[INFO]${NC} Using default settings."
else
    INTERACTIVE_MODE=true
    echo -e "\n${GREEN}--- Interactive Configuration ---${NC}"
    
    read -p "1. Container name [${CONTAINER_NAME}]: " new_name; CONTAINER_NAME=${new_name:-$CONTAINER_NAME}

    echo "2. Restart policy:"
    echo "   1) no"; echo "   2) on-failure"; echo "   3) always"; echo "   4) unless-stopped"
    while true; do
        read -p "   Enter your choice [4]: " policy_choice; policy_choice=${policy_choice:-4}
        case $policy_choice in
            1) RESTART_POLICY="no"; break ;; 2) RESTART_POLICY="on-failure"; break ;;
            3) RESTART_POLICY="always"; break ;; 4) RESTART_POLICY="unless-stopped"; break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid selection." ;;
        esac
    done

    echo "3. Published port:"
    while true; do
        read -p "   Enter port [${PUBLISHED_PORT}]: " new_port; new_port=${new_port:-$PUBLISHED_PORT}
        if ss -tuln | grep -q ":${new_port} "; then
            echo -e "${YELLOW}[WARN]${NC} Port ${new_port} appears to be in use."
            if ! prompt_yes_no "   Select a different port?" "Y"; then
                if prompt_yes_no "${RED}[DANGER]${NC} Continue with port ${new_port} anyway?" "N"; then
                    PUBLISHED_PORT=$new_port; break
                fi
            fi
        else
            PUBLISHED_PORT=$new_port; break
        fi
    done
    
    echo "4. User and Group IDs:"
    read -p "   Enter PUID (User ID) [${PUID}]: " new_puid; PUID=${new_puid:-$PUID}
    read -p "   Enter PGID (Group ID) [${PGID}]: " new_pgid; PGID=${new_pgid:-$PGID}
fi

# 2. Validate Persistent Volume
handle_persistent_volume

# 3. Final File Generation
echo
echo -e "${GREEN}[INFO]${NC} Creating 'docker-compose.yml'..."

cat > docker-compose.yml << EOF
services:
  delve:
    image: aarondyck/delve:latest
    container_name: ${CONTAINER_NAME}
    restart: ${RESTART_POLICY}
    ports:
      - "${PUBLISHED_PORT}:5001"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
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
