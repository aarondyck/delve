#!/bin/bash
# This script manages the container exclusion list for the Delve logging daemon.
# It is intended to be run via 'docker exec'.

# --- Configuration ---
EXCLUDE_FILE="/data/exclude.list"
DATA_DIR="/data"

# --- Helper Functions ---

# Function to print messages with colors for better readability.
echo_info() { echo -e "\e[32m[INFO]\e[0m $1"; }
echo_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
echo_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }

# Function to pause the script until the user presses a key.
press_any_key() {
    echo
    read -n 1 -s -r -p "Press any key to exit..."
    echo
}

# Function to display the help message.
show_help() {
    echo "Delve Log Management Script"
    echo "---------------------------"
    echo "Usage: $0 [command] [container_names...]"
    echo
    echo "Commands:"
    echo "  (no command)          Displays the current list of excluded containers."
    echo "  -x, --exclude <name>  Adds one or more containers to the exclusion list."
    echo "  -r, --remove <name>   Removes one or more containers from the exclusion list."
    echo "  -c, --clear           Removes all entries from the exclusion list."
    echo "  -h, --help            Displays this help message."
    echo
}

# Function to print the current exclusion list (the default action).
print_exclusion_list() {
    echo_info "Checking exclusion list at ${EXCLUDE_FILE}..."
    echo
    echo "--- Containers Excluded from Logging ---"

    if [ ! -s "$EXCLUDE_FILE" ]; then
        echo "No containers are currently excluded from logging."
        return
    fi

    # Get a list of all container names (running or not) for validation.
    mapfile -t all_containers < <(docker ps -a --format '{{.Names}}')

    # Read the exclusion file line by line.
    while IFS= read -r container_name || [[ -n "$container_name" ]]; do
        is_running=false
        # Check if the excluded container exists.
        for running_name in "${all_containers[@]}"; do
            if [[ "$container_name" == "$running_name" ]]; then
                is_running=true
                break
            fi
        done

        if $is_running; then
            echo "  - ${container_name}"
        else
            echo -e "  - ${container_name} \e[33m(not a currently running or stopped container)\e[0m"
        fi
    done < "$EXCLUDE_FILE"
    echo "----------------------------------------"
}

# --- Main Logic ---

# Ensure the exclude file and its directory exist.
mkdir -p "$(dirname "$EXCLUDE_FILE")"
touch "$EXCLUDE_FILE"

# If no arguments are provided, print the list and exit.
if [ $# -eq 0 ]; then
    print_exclusion_list
    exit 0
fi

# Parse command-line arguments.
while (( "$#" )); do
    case "$1" in
        -h|--help)
            show_help
            press_any_key
            exit 0
            ;;
        -c|--clear)
            echo_warn "This will remove all entries from the exclusion list."
            read -p "Are you sure you want to clear the entire list? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                > "$EXCLUDE_FILE"
                echo_info "Exclusion list has been cleared."
            else
                echo_info "Operation cancelled."
            fi
            press_any_key
            exit 0
            ;;
        -x|--exclude)
            shift # Remove the '-x' or '--exclude' flag itself.
            if [ $# -eq 0 ] || [[ "${1:0:1}" == "-" ]]; then
                echo_error "Error: The --exclude flag requires at least one container name."
                exit 1
            fi
            
            containers_to_add=()
            while (( "$#" )) && [[ ${1:0:1} != "-" ]]; do
                container_name="$1"
                # Validate if the container exists (running or stopped).
                if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                    echo_warn "Container '${container_name}' does not exist."
                    read -p "Add it to the exclusion list anyway? (y/n) " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        containers_to_add+=("$container_name")
                    else
                        echo_info "Skipping '${container_name}'."
                    fi
                else
                    containers_to_add+=("$container_name")
                fi
                shift
            done

            for name in "${containers_to_add[@]}"; do
                # Add the container to the list if it's not already there.
                if grep -qxF "$name" "$EXCLUDE_FILE"; then
                    echo_warn "Container '${name}' is already in the exclusion list."
                else
                    echo "$name" >> "$EXCLUDE_FILE"
                    echo_info "Added '${name}' to the exclusion list."
                fi
            done
            ;;
        -r|--remove)
            shift # Remove the '-r' or '--remove' flag.
            if [ $# -eq 0 ] || [[ "${1:0:1}" == "-" ]]; then
                echo_error "Error: The --remove flag requires at least one container name."
                exit 1
            fi

            while (( "$#" )) && [[ ${1:0:1} != "-" ]]; do
                container_name="$1"
                # Check if the container is in the list before trying to remove it.
                if grep -qxF "$container_name" "$EXCLUDE_FILE"; then
                    # Use grep -v to create a new file without the specified container.
                    grep -vxF "$container_name" "$EXCLUDE_FILE" > "${EXCLUDE_FILE}.tmp" && mv "${EXCLUDE_FILE}.tmp" "$EXCLUDE_FILE"
                    echo_info "Removed '${container_name}' from the exclusion list."
                else
                    echo_warn "Container '${container_name}' was not found in the exclusion list."
                fi
                shift
            done
            ;;
        *)
            echo_error "Unknown flag: $1"
            show_help
            exit 1
            ;;
    esac
done

# After adding or removing, ask to print the list.
read -p "Would you like to print the current exclusion list? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_exclusion_list
else
    press_any_key
fi

exit 0
