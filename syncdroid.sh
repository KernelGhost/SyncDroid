#!/usr/bin/env bash

# --------------------------------------------------------------------------------
# Name: 'syncdroid'
# Role: Sync specified folders stored on an Android smartphone to an online or
# local 'rclone' remote.
# Usage: syncdroid (--sync | --verify) [--local]
#        syncdroid (-s | -v) [-l]
# * '--sync' or '-s'   --> Sync remote with selected directories.
# * '--verify' or '-v' --> Verify integrity of files on a remote using checksums.
# * '--local' or '-l'  --> Utilise the local remote instead of the online remote.

# Exit Status Codes:
# * 0 --> Success.
# * 1 --> Invalid argument(s).
# * 2 --> No internet connection.
# * 3 --> Missing directory list file.
# * 4 --> Empty directory list file.
# * 5 --> Incorrect 'rclone' configuration file password.
# * 6 --> Rclone remote does not exist.
# --------------------------------------------------------------------------------

function syncdroid() {
    # CONSTANTS - USER SETTINGS
    local USER_SETTINGS_FILE_PATH="${HOME}/.config/syncdroid/config.sh"

    # Capture settings specified within the configuration file.
    # Using a subshell prevents pollution of the environment with global variables.
    eval "$(
        (
            # Source the configuration file.
            source "$USER_SETTINGS_FILE_PATH"

            # Print out the variables in a way that can be processed by 'eval'.
            echo "local ONLINE_REMOTE_NAME=\"$OnlineRemoteName\""
            echo "local LOCAL_REMOTE_NAME=\"$LocalRemoteName\""
            echo "local DEVICE_ROOT_PATH=\"$DevRootPath\""
            echo "local DIR_SYNC_LIST_PATH=\"$DirSyncListPath\""
            echo "local ONLINE_REMOTE_PATH=\"$OnlineRemotePath\""
            echo "local LOCAL_REMOTE_PATH=\"$LocalRemotePath\""
            echo "local LOCAL_CONNECTION_TEST_URL=\"$LocalConnectionTestURL\""
            echo "local ONLINE_CONNECTION_TEST_URL=\"$OnlineConnectionTestURL\""
            echo "local CONNECTION_TEST_TIMEOUT=\"$ConnectionTestTimeout\""
            echo "local CONNECTION_TEST_PACKETS=\"$ConnectionTestPackets\""
        )
    )"

    # Make the variables read-only.
    readonly ONLINE_REMOTE_NAME LOCAL_REMOTE_NAME \
            DEVICE_ROOT_PATH DIR_SYNC_LIST_PATH ONLINE_REMOTE_PATH \
            LOCAL_REMOTE_PATH LOCAL_CONNECTION_TEST_URL \
            ONLINE_CONNECTION_TEST_URL CONNECTION_TEST_TIMEOUT \
            CONNECTION_TEST_PACKETS

    # CONSTANTS - ANSI ESCAPE SEQUENCES
    local ANSI_RED="\e[1;31m"
    local ANSI_YELLOW="\e[1;33m"
    local ANSI_GREEN="\e[1;32m"
    local ANSI_BLUE="\e[1;34m"
    local ANSI_CLEAR="\e[0m"
    readonly ANSI_RED
    readonly ANSI_YELLOW
    readonly ANSI_GREEN
    readonly ANSI_BLUE
    readonly ANSI_CLEAR

    # VARIABLES
    local SYNC_FLAG=0
    local VERIFY_FLAG=0
    local LOCAL_FLAG=0
    local REMOTE
    local REMOTE_NAME
    local REMOTE_PATH
    local IMPORTED_FILE
    local LOCAL_DIRS
    local REMOTE_DIRS
    local ABANDONED_DIRS
    local ctr
    local element
    local user_choice

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -s|--sync)
                if [ "$VERIFY_FLAG" -eq 1 ]; then
                    echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                    return 1
                fi
                SYNC_FLAG=1
                ;;
            -v|--verify)
                if [ "$SYNC_FLAG" -eq 1 ]; then
                    echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                    return 1
                fi
                VERIFY_FLAG=1
                ;;
            -l|--local)
                LOCAL_FLAG=1
                ;;
            --*)
                echo -e "${ANSI_YELLOW}[WARN]${ANSI_CLEAR} Invalid argument '$1'. Ignoring."
                ;;
            -*)
                # Handle combined arguments (e.g., '-vl' and '-vs').
                for (( ctr=1; ctr<${#1}; ctr++ )); do
                    case "${1:ctr:1}" in
                        s)
                            if [ "$VERIFY_FLAG" -eq 1 ]; then
                                echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                                return 1
                            fi
                            SYNC_FLAG=1
                            ;;
                        v)
                            if [ "$SYNC_FLAG" -eq 1 ]; then
                                echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                                return 1
                            fi
                            VERIFY_FLAG=1
                            ;;
                        l)
                            LOCAL_FLAG=1
                            ;;
                        *)
                            echo -e "${ANSI_YELLOW}[WARN]${ANSI_CLEAR} Invalid argument '-${1:ctr:1}'. Ignoring."
                            ;;
                    esac
                done
                ;;
            *)
                echo -e "${ANSI_YELLOW}[WARN]${ANSI_CLEAR} Invalid argument '$1'. Ignoring."
                ;;
        esac
        shift
    done

    # Ensure at least one of '--sync' or '--verify' is specified.
    if [ "$SYNC_FLAG" -eq 0 ] && [ "$VERIFY_FLAG" -eq 0 ]; then
        echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} You must specify either '--sync' (-s) or '--verify' (-v)! Quitting."
        return 1
    fi

    # Set rclone remote name and path.
    if [ "$LOCAL_FLAG" -eq 0 ]; then
        # Name
        REMOTE_NAME="$ONLINE_REMOTE_NAME"

        # Path
        REMOTE_PATH="$ONLINE_REMOTE_PATH"

        # Name + Path (e.g. Remote:path/to/directory)
        REMOTE="${ONLINE_REMOTE_NAME}:${ONLINE_REMOTE_PATH}"
    else
        # Name
        REMOTE_NAME="$LOCAL_REMOTE_NAME"

        # Path
        REMOTE_PATH="$LOCAL_REMOTE_PATH"

        # Name + Path (e.g. Remote:path/to/directory)
        REMOTE="${LOCAL_REMOTE_NAME}:${LOCAL_REMOTE_PATH}"
    fi

    # TEST CONNECTION
    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Testing connection..."
    if [ "$LOCAL_FLAG" -eq 0 ]; then
        if ping -q -c $CONNECTION_TEST_PACKETS -W $CONNECTION_TEST_TIMEOUT $ONLINE_CONNECTION_TEST_URL &>/dev/null; then
            echo -e "${ANSI_GREEN}[SUCCESS]${ANSI_CLEAR} Internet connection present!\n"
        else
            echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} No internet connection! Quitting."
            return 2
        fi
    else
        if ping -q -c $CONNECTION_TEST_PACKETS -W $CONNECTION_TEST_TIMEOUT $LOCAL_CONNECTION_TEST_URL &>/dev/null; then
            echo -e "${ANSI_GREEN}[SUCCESS]${ANSI_CLEAR} SFTP host reachable!\n"
        else
            echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} SFTP host unreachable! Quitting."
            return 2
        fi
    fi

    # CHECK DIRECTORY LIST EXISTS
    if [ ! -f "${DIR_SYNC_LIST_PATH}" ]; then
        echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} The file containing the directories to sync is missing! Quitting."
        return 3
    fi

    # Store each line within the directory list file in an array.
    # Note: This approach ignores empty/blank lines within the file.
    IFS=$'\n' read -d '' -r -a IMPORTED_FILE < "${DIR_SYNC_LIST_PATH}"

    # Remove comments from the array.
    for ((ctr=0; ctr<${#IMPORTED_FILE[@]}; ctr++)); do
        # Remove lines starting with '#'.
        if [[ ${IMPORTED_FILE[ctr]} != "#"* ]]; then
            # Remove everything following the first '#'.
            local trimmed_dir
            trimmed_dir="${IMPORTED_FILE[ctr]%%#*}"

            # Trim whitespace from beginning and end.
            trimmed_dir="${trimmed_dir%"${trimmed_dir##*[![:space:]]}"}"
            trimmed_dir="${trimmed_dir#"${trimmed_dir%%[![:space:]]*}"}"

            # Remove leading and trailing double quotation marks, if they exist.
            # Note: This allows users to specify directory names with leading/trailing whitespace.
            # Note: Checking both quotation marks are present first allows for directories containing ".
            if [[ "$trimmed_dir" =~ ^\".*\"$ ]]; then
                # Remove leading double quote.
                trimmed_dir="${trimmed_dir#\"}"
                # Remove trailing double quote.
                trimmed_dir="${trimmed_dir%\"}"
            fi

            # Store the trimmed directory.
            # Note: Stored paths are relative to the device root (e.g., "DCIM", "My Folder/Private", etc.).
            if [ -n "$trimmed_dir" ]; then
                LOCAL_DIRS+=("$trimmed_dir")
            fi
        fi
    done

    # CHECK FOR EMPTY DIRECTORY ARRAY
    if [ ${#LOCAL_DIRS[@]} -eq 0 ]; then
        echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} No directories were specified! Quitting."
        return 4
    fi
    
    # List the paths to the directories.
    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Directories:"
    for ((ctr=0; ctr<${#LOCAL_DIRS[@]}; ctr++)); do
        echo "$((ctr + 1)). \"${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}\""
    done

    # Newline
    echo ""

    # Store rclone configuration password, making it available to child processes (i.e., rclone).
    read -r -s -p "Enter password to unlock 'rclone' configuration file: " RCLONE_CONFIG_PASS
    export RCLONE_CONFIG_PASS

    # Newline
    echo ""

    # TEST SUPPLIED PASSWORD
    # Note: '--ask-password=false' prevents rclone interactively requesting the password if 'RCLONE_CONFIG_PASS' contains the wrong password.
    if ! rclone config show --ask-password=false &>/dev/null; then
        echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Incorrect password! Quitting."
        return 5
    else
        echo -e "${ANSI_GREEN}CORRECT PASSWORD!${ANSI_CLEAR}\n"
    fi

    # ENSURE SPECIFIED REMOTE EXISTS
    if [ -z $(rclone listremotes --ask-password=false | grep -E "^${REMOTE_NAME}:$") ]; then
        echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Remote '${REMOTE_NAME}' does not exist! Quitting."
        return 6
    fi

    # Create the directory to use if it does not already exist.
    rclone mkdir "$REMOTE" --ask-password=false

    # REMOVE ABANDONED DIRECTORIES
    # Identify directories present on remote.
    # Note: 'awk' is required to remove trailing forward slashes after directory names.
    readarray -t REMOTE_DIRS < <(rclone lsf --dirs-only $REMOTE | awk '{sub(/\/$/, "", $0); print}')

    # Identify directories on remote that are not listed for synchronisation (abandoned directories).
    for element in "${REMOTE_DIRS[@]}"; do
        if ! [[ " ${LOCAL_DIRS[*]} " =~ " ${element} " ]]; then
            # List directory for deletion.
            ABANDONED_DIRS+=("$element")
        fi
    done

    # Notify user if abandoned directories were found.
    if [ ${#ABANDONED_DIRS[@]} -gt 0 ]; then
        echo -e "${ANSI_YELLOW}[WARN]${ANSI_CLEAR} The following abandoned directories were detected:"
        for ((ctr=0; ctr<${#ABANDONED_DIRS[@]}; ctr++)); do
            echo "$((ctr + 1)). \"${ABANDONED_DIRS[ctr]}\""
        done

        # Newline
        echo ""

        # Delete abandoned directories after asking user.
        while true; do
            read -r -p "Delete abandoned directories from the remote? (y/n): " user_choice
            case "$user_choice" in
                [Yy]* )
                    # Loop through and delete abandoned directories.
                    for ((ctr=0; ctr<${#ABANDONED_DIRS[@]}; ctr++)); do
                        echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Deleting \"${ABANDONED_DIRS[ctr]}\" ${ANSI_GREEN}($((ctr + 1))/${#ABANDONED_DIRS[@]})${ANSI_CLEAR}"
                        rclone purge "${REMOTE}/${ABANDONED_DIRS[ctr]}"
                    done

                    # Newline.
                    echo ""

                    # Break out of the loop.
                    break
                    ;;
                [Nn]* )
                    # Provide feedback.
                    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Leaving abandoned directories untouched.\n"

                    # Break out of the loop.
                    break
                    ;;
                * )
                    echo -e "${ANSI_RED}[ERR]${ANSI_CLEAR} Invalid response!"
                    ;;
            esac
        done
    fi

    # RUN SYNC OR VERIFICATION
    echo -e -n "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Commencing "
    echo "$( [ "$VERIFY_FLAG" -eq 1 ] && echo "verification" || echo "synchronisation" )..."
    for ((ctr=0; ctr<${#LOCAL_DIRS[@]}; ctr++)); do
        # Check if the directory exists.
        if [[ -d "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" ]]; then
            if [ "$SYNC_FLAG" -eq 1 ]; then
                echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Syncing \"${LOCAL_DIRS[ctr]}\" ${ANSI_GREEN}($((ctr + 1))/${#LOCAL_DIRS[@]})${ANSI_CLEAR}"
                rclone sync "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" "${REMOTE}/${LOCAL_DIRS[ctr]}" --progress
            else
                echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Verifying \"${LOCAL_DIRS[ctr]}\" ${ANSI_GREEN}($((ctr + 1))/${#LOCAL_DIRS[@]})${ANSI_CLEAR}"
                if [[ $(rclone config show "$REMOTE_PATH" | grep "^type = .*$" | sed "s/type = //") == "crypt" ]]; then
                    rclone cryptcheck "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" "${REMOTE}/${LOCAL_DIRS[ctr]}" --progress
                else
                    rclone check "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" "${REMOTE}/${LOCAL_DIRS[ctr]}" --progress
                fi
            fi
        else
            echo -e "${ANSI_YELLOW}[WARN]${ANSI_CLEAR} The directory \"${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}\" does not exist. Skipping..."
        fi

        # Newline.
        echo ""
    done

    # Clear rclone configuration file password.
    unset RCLONE_CONFIG_PASS

    # Provide feedback.
    echo -e "${ANSI_GREEN}FINISHED!${ANSI_CLEAR}"

    # Exit.
    return 0
}
