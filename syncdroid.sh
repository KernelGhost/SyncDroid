#!/usr/bin/env bash

# --------------------------------------------------------------------------------
# Name: 'syncdroid'
# Role: Sync specified folders stored on a unix system to an online or local
#       rclone remote.
# Usage: syncdroid (--sync | --verify) [--local]
#        syncdroid (-s | -v) [-l]
# * '--sync' or '-s'   --> Sync remote with selected directories.
# * '--verify' or '-v' --> Verify integrity of files on a remote using checksums.
# * '--local' or '-l'  --> Utilise the local remote instead of the online remote.

# Exit Status Codes:
# * 0  --> Success.
# * 1  --> Missing syncdroid configuration file.
# * 2  --> Invalid argument(s).
# * 3  --> No internet connection.
# * 4  --> Missing directory list file.
# * 5  --> Empty directory list file.
# * 6  --> Incorrect 'rclone' configuration file password.
# * 7  --> Rclone remote does not exist.
# * 8  --> SSH private key not found.
# * 9  --> Failed to compute SSH private key fingerprint.
# * 10 --> Failed to add SSH private key to 'ssh-agent'.
# --------------------------------------------------------------------------------

function syncdroid() {
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

    # CONSTANTS - USER SETTINGS
    local USER_SETTINGS_FILE_PATH="${HOME}/.config/syncdroid/config.sh"

    # Check the configuration file exists.
    if [[ ! -f "$USER_SETTINGS_FILE_PATH" ]]; then
        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Configuration file '$USER_SETTINGS_FILE_PATH' is missing! Quitting."
        return 1
    fi

    # Capture settings specified within the configuration file.
    # Using a subshell prevents pollution of the environment with global variables.
    eval "$(
        (
            # Source the configuration file.
            source "$USER_SETTINGS_FILE_PATH"

            # Print out the variables in a way that can be processed by 'eval'.
            echo "local OFFSITE_REMOTE_NAME=\"$OffsiteRemoteName\""
            echo "local ONSITE_REMOTE_NAME=\"$OnsiteRemoteName\""
            echo "local PRIVATE_KEY_PATH=\"$SSHPrivateKeyPath\""
            echo "local DEVICE_ROOT_PATH=\"$DevRootPath\""
            echo "local DIR_SYNC_LIST_PATH=\"$DirSyncListPath\""
            echo "local OFFSITE_REMOTE_PATH=\"$OffsiteRemotePath\""
            echo "local ONSITE_REMOTE_PATH=\"$OnsiteRemotePath\""
            echo "local ONSITE_CONNECTION_TEST_PORT=\"$OnsiteConnectionTestPort\""
            echo "local ONSITE_CONNECTION_TEST_URL=\"$OnsiteConnectionTestURL\""
            echo "local OFFSITE_CONNECTION_TEST_URL=\"$OffsiteConnectionTestURL\""
            echo "local CONNECTION_TEST_TIMEOUT=\"$ConnectionTestTimeout\""
            echo "local CONNECTION_TEST_PACKETS=\"$ConnectionTestPackets\""
        )
    )"

    # Make the variables read-only.
    readonly OFFSITE_REMOTE_NAME ONSITE_REMOTE_NAME PRIVATE_KEY_PATH \
            DEVICE_ROOT_PATH DIR_SYNC_LIST_PATH OFFSITE_REMOTE_PATH \
            ONSITE_REMOTE_PATH ONSITE_CONNECTION_TEST_PORT \
            ONSITE_CONNECTION_TEST_URL OFFSITE_CONNECTION_TEST_URL \
            CONNECTION_TEST_TIMEOUT CONNECTION_TEST_PACKETS

    # VARIABLES
    local SYNC_FLAG=0
    local VERIFY_FLAG=0
    local LOCAL_FLAG=0
    local REMOTE
    local REMOTE_NAME
    local ctr
    local user_choice
    local -a IMPORTED_FILE=()
    local -a LOCAL_DIRS=()
    local -a REMOTE_DIRS=()
    local -a REMOTE_FILES=()
    local -a ABANDONED_DIRS=()
    local -a ABANDONED_FILES=()
    local -a PRUNED_ABANDONED_DIRS=()
    local -a sorted_abandoned=()

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -s|--sync)
                if [ "$VERIFY_FLAG" -eq 1 ]; then
                    echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                    return 2
                fi
                SYNC_FLAG=1
                ;;
            -v|--verify)
                if [ "$SYNC_FLAG" -eq 1 ]; then
                    echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                    return 2
                fi
                VERIFY_FLAG=1
                ;;
            -l|--local)
                LOCAL_FLAG=1
                ;;
            --*)
                echo -e "${ANSI_YELLOW}[WARNING]${ANSI_CLEAR} Invalid argument '$1'. Ignoring."
                ;;
            -*)
                # Handle combined arguments (e.g., '-vl' and '-vs').
                for (( ctr=1; ctr<${#1}; ctr++ )); do
                    case "${1:ctr:1}" in
                        s)
                            if [ "$VERIFY_FLAG" -eq 1 ]; then
                                echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                                return 2
                            fi
                            SYNC_FLAG=1
                            ;;
                        v)
                            if [ "$SYNC_FLAG" -eq 1 ]; then
                                echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Cannot specify both '--sync' (-s) and '--verify' (-v)! Quitting."
                                return 2
                            fi
                            VERIFY_FLAG=1
                            ;;
                        l)
                            LOCAL_FLAG=1
                            ;;
                        *)
                            echo -e "${ANSI_YELLOW}[WARNING]${ANSI_CLEAR} Invalid argument '-${1:ctr:1}'. Ignoring."
                            ;;
                    esac
                done
                ;;
            *)
                echo -e "${ANSI_YELLOW}[WARNING]${ANSI_CLEAR} Invalid argument '$1'. Ignoring."
                ;;
        esac
        shift
    done

    # Ensure at least one of '--sync' or '--verify' is specified.
    if [ "$SYNC_FLAG" -eq 0 ] && [ "$VERIFY_FLAG" -eq 0 ]; then
        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} You must specify either '--sync' (-s) or '--verify' (-v)! Quitting."
        return 2
    fi

    # Set rclone remote name and path.
    if [ "$LOCAL_FLAG" -eq 0 ]; then
        # Name
        REMOTE_NAME="$OFFSITE_REMOTE_NAME"

        # Name + Path (e.g. Remote:path/to/directory)
        REMOTE="${OFFSITE_REMOTE_NAME}:${OFFSITE_REMOTE_PATH}"
    else
        # Name
        REMOTE_NAME="$ONSITE_REMOTE_NAME"

        # Name + Path (e.g. Remote:path/to/directory)
        REMOTE="${ONSITE_REMOTE_NAME}:${ONSITE_REMOTE_PATH}"
    fi

    # TEST CONNECTION
    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Testing connection..."
    if [ "$LOCAL_FLAG" -eq 0 ]; then
        if ping -q -c "$CONNECTION_TEST_PACKETS" -W "$CONNECTION_TEST_TIMEOUT" "$OFFSITE_CONNECTION_TEST_URL" &>/dev/null; then
            echo -e "${ANSI_GREEN}[SUCCESS]${ANSI_CLEAR} Internet connection present!\n"
        else
            echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} No internet connection! Quitting."
            return 3
        fi
    else
        if nc -z -w "$CONNECTION_TEST_TIMEOUT" "$ONSITE_CONNECTION_TEST_URL" "$ONSITE_CONNECTION_TEST_PORT" &>/dev/null; then
            echo -e "${ANSI_GREEN}[SUCCESS]${ANSI_CLEAR} SFTP host reachable!\n"
        else
            echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} SFTP host unreachable! Quitting."
            return 3
        fi
    fi

    # CHECK DIRECTORY LIST EXISTS
    if [ ! -f "${DIR_SYNC_LIST_PATH}" ]; then
        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} The file containing the directories to sync is missing! Quitting."
        return 4
    fi

    # Store each line within the directory list file in an array.
    # Note: This approach ignores empty/blank lines within the file.
    mapfile -t IMPORTED_FILE < "$DIR_SYNC_LIST_PATH"

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

            # Remove all trailing slashes (if present).
            trimmed_dir="${trimmed_dir%"${trimmed_dir##*[!/]}"}"

            # Store the trimmed directory.
            # Note: Stored paths are relative to the device root (e.g., "DCIM", "My Folder/Private", etc.).
            if [ -n "$trimmed_dir" ]; then
                LOCAL_DIRS+=("$trimmed_dir")
            fi
        fi
    done

    # CHECK FOR EMPTY DIRECTORY ARRAY
    if [ ${#LOCAL_DIRS[@]} -eq 0 ]; then
        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} No directories were specified! Quitting."
        return 5
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
        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Incorrect password! Quitting."
        return 6
    else
        echo -e "${ANSI_GREEN}CORRECT PASSWORD!${ANSI_CLEAR}\n"
    fi

    # ENSURE SPECIFIED REMOTE EXISTS
    if ! rclone listremotes --ask-password=false | grep -Fxq "${REMOTE_NAME}:"; then
        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Remote '${REMOTE_NAME}' does not exist! Quitting."
        return 7
    fi

    # ADD SSH PRIVATE KEY IF REQUIRED
    if [ "$LOCAL_FLAG" -eq 1 ]; then
        if [[ -n "$PRIVATE_KEY_PATH" ]]; then
            # Feedback
            echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Private SSH key specified."

            # Ensure the key exists
            if [[ ! -f "$PRIVATE_KEY_PATH" ]]; then
                echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Private key not found at specified path! Quitting."
                return 8
            fi

            # Silently start 'ssh-agent' if not already running
            if [ -z "$SSH_AUTH_SOCK" ]; then
                eval "$(ssh-agent -s)" &>/dev/null
            fi

            # Compute fingerprint of the private key (uses embedded public part, avoiding a passphrase prompt)
            local key_fp
            key_fp="$(ssh-keygen -lf "$PRIVATE_KEY_PATH" 2>/dev/null | awk '{print $2}')"
            if [[ -z "$key_fp" ]]; then
                echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Failed to compute private key fingerprint! Quitting."
                return 9
            fi

            # Check if a key with this fingerprint is already loaded in ssh-agent
            if ssh-add -l &>/dev/null; then
                if ssh-add -l 2>/dev/null | awk '{print $2}' | grep -Fxq "$key_fp"; then
                    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Private key already loaded into ssh-agent.\n"
                else
                    # The private key is not in the list of loaded keys
                    # Add private key to 'ssh-agent'
                    if ! ssh-add "$PRIVATE_KEY_PATH"; then
                        echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Failed to add private key! Quitting."
                        return 10
                    fi

                    # Newline
                    echo ""
                fi
            else
                # No keys currently loaded
                # Add private key to 'ssh-agent'
                if ! ssh-add "$PRIVATE_KEY_PATH"; then
                    echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Failed to add private key! Quitting."
                    return 10
                fi

                # Newline
                echo ""
            fi
        fi
    fi

    # Create the directory to use if it does not already exist.
    rclone mkdir "$REMOTE" --ask-password=false

    # REMOVE ABANDONED DIRECTORIES & FILES
    # Provide feedback.
    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Enumerating directories and files. This may take a while."

    # Recursively identify directories present on remote.
    # Note: 'awk' is required to remove trailing forward slashes after directory names.
    mapfile -t REMOTE_DIRS < <(rclone lsf --dirs-only --recursive "$REMOTE" | awk '{sub(/\/$/, "", $0); print}')

    # Identify directories on the remote that are not listed for synchronisation (abandoned directories).
    for remote_dir in "${REMOTE_DIRS[@]}"; do
        found=false
        for local_dir in "${LOCAL_DIRS[@]}"; do
            # We want to retain every remote directory that satisfies any one of the following requirements:
            # 1. The remote directory matches a specified local directory exactly (e.g. "Documents" & "Documents").
            # 2. The remote directory is a subdirectory of a specified local directory (e.g. "Documents/Scans/2025" [REMOTE] & "Documents" [LOCAL]).
            # 3. The remote directory is a parent of a specified local directory (e.g. "Documents" [REMOTE] & "Documents/Scans/2025" [LOCAL]).
            # These checks are required since 'lsf --dirs-only --recursive' lists the paths of ALL directories on the remote.
            # - We do not want to erroneously list a parent directory on the remote as abandoned when a subdirectory is listed for synchronisation.
            # - We do not want to erroneously list a child directory on the remote as abandoned when a parent directory is listed for synchronisation.
            # Note: Subdirectories (of a specified local parent directory) that have since been deleted locally but remain present on the remote are not flagged as abandoned.
            #       This is because rclone automatically detects and removes missing subdirectories during synchronisation of a specified parent directory.
            #       This logic only identifies remote directories as abandoned if they are no longer associated with any specified local directory.
            if [[ "$remote_dir" == "$local_dir" || "$remote_dir/" == "$local_dir/"* || "$local_dir/" == "$remote_dir/"* ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            ABANDONED_DIRS+=("$remote_dir")
        fi
    done

    # Remove abandoned directories that are children of other abandoned directories
    if [ ${#ABANDONED_DIRS[@]} -gt 0 ]; then
        # Sort abandoned directories lexicographically so parents precede children
        mapfile -t sorted_abandoned < <(
            printf '%s\n' "${ABANDONED_DIRS[@]}" | sort
        )

        # Prune any entry that is a child of a previously kept entry
        for dir in "${sorted_abandoned[@]}"; do
            skip=false
            for kept in "${PRUNED_ABANDONED_DIRS[@]}"; do
                if [[ "$dir" == "$kept/"* ]]; then
                    skip=true
                    break
                fi
            done
            if [[ "$skip" == false ]]; then
                PRUNED_ABANDONED_DIRS+=("$dir")
            fi
        done
    fi

    # Recursively identify files present on remote.
    mapfile -t REMOTE_FILES < <(rclone lsf --files-only --recursive "$REMOTE")

    # Identify files on the remote that are no longer specified for synchronisation (abandoned files).
    for remote_file in "${REMOTE_FILES[@]}"; do
        # If this file lives under an abandoned directory, there is no need to list it separately.
        skip=false
        for dir in "${PRUNED_ABANDONED_DIRS[@]}"; do
            if [[ "$remote_file" == "$dir/"* ]]; then
                skip=true
                break
            fi
        done

        # If this file lives under an abandoned directory, skip the remainder of this code block.
        if [[ "$skip" == true ]]; then
            continue
        fi

        # If this file does not live under an abandoned directory, check if it is associated with a local directory
        found=false
        for local_dir in "${LOCAL_DIRS[@]}"; do
            if [[ "$remote_file" == "$local_dir" || "$remote_file" == "$local_dir/"* ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            ABANDONED_FILES+=("$remote_file")
        fi
    done

    # Notify user if abandoned directories or files were found.
    # Directories
    if [ ${#PRUNED_ABANDONED_DIRS[@]} -gt 0 ]; then
        echo -e "${ANSI_YELLOW}[WARNING]${ANSI_CLEAR} The following abandoned directories were detected:"
        for ((ctr=0; ctr<${#PRUNED_ABANDONED_DIRS[@]}; ctr++)); do
            echo "$((ctr + 1)). \"${PRUNED_ABANDONED_DIRS[ctr]}\""
        done

        # Newline
        echo ""

        # Delete abandoned directories after asking user.
        while true; do
            read -r -p "Delete abandoned directories from the remote? (y/n): " user_choice
            case "$user_choice" in
                [Yy]* )
                    # Loop through and delete abandoned directories.
                    for ((ctr=0; ctr<${#PRUNED_ABANDONED_DIRS[@]}; ctr++)); do
                        echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Deleting \"${PRUNED_ABANDONED_DIRS[ctr]}\" ${ANSI_GREEN}($((ctr + 1))/${#PRUNED_ABANDONED_DIRS[@]})${ANSI_CLEAR}"
                        rclone purge "${REMOTE}/${PRUNED_ABANDONED_DIRS[ctr]}"
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
                    echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Invalid response!"
                    ;;
            esac
        done
    fi

    # Files
    if [ ${#ABANDONED_FILES[@]} -gt 0 ]; then
        echo -e "${ANSI_YELLOW}[WARNING]${ANSI_CLEAR} The following abandoned files were detected:"
        for ((ctr=0; ctr<${#ABANDONED_FILES[@]}; ctr++)); do
            echo "$((ctr + 1)). \"${ABANDONED_FILES[ctr]}\""
        done

        # Newline
        echo ""

        # Delete abandoned files after asking user.
        while true; do
            read -r -p "Delete abandoned files from the remote? (y/n): " user_choice
            case "$user_choice" in
                [Yy]* )
                    # Loop through and delete abandoned files.
                    for ((ctr=0; ctr<${#ABANDONED_FILES[@]}; ctr++)); do
                        echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Deleting \"${ABANDONED_FILES[ctr]}\" ${ANSI_GREEN}($((ctr + 1))/${#ABANDONED_FILES[@]})${ANSI_CLEAR}"
                        rclone delete "${REMOTE}/${ABANDONED_FILES[ctr]}"
                    done

                    # Newline
                    echo ""

                    # Break out of the loop.
                    break
                    ;;
                [Nn]* )
                    # Provide feedback.
                    echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Leaving abandoned files untouched.\n"

                    # Break out of the loop.
                    break
                    ;;
                * )
                    echo -e "${ANSI_RED}[ERROR]${ANSI_CLEAR} Invalid response!"
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
                rclone sync "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" "${REMOTE}/${LOCAL_DIRS[ctr]}" --create-empty-src-dirs --progress
            else
                echo -e "${ANSI_BLUE}[INFO]${ANSI_CLEAR} Verifying \"${LOCAL_DIRS[ctr]}\" ${ANSI_GREEN}($((ctr + 1))/${#LOCAL_DIRS[@]})${ANSI_CLEAR}"
                if [[ $(rclone config show "$REMOTE_NAME" | grep "^type = .*$" | sed "s/type = //") == "crypt" ]]; then
                    rclone cryptcheck "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" "${REMOTE}/${LOCAL_DIRS[ctr]}" --progress
                else
                    rclone check "${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}" "${REMOTE}/${LOCAL_DIRS[ctr]}" --progress
                fi
            fi
        else
            echo -e "${ANSI_YELLOW}[WARNING]${ANSI_CLEAR} The directory \"${DEVICE_ROOT_PATH}/${LOCAL_DIRS[ctr]}\" does not exist. Skipping..."
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
