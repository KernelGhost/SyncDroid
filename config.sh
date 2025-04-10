#!/usr/bin/env bash

############################## SYNCDROID SETTINGS ##############################
# ------------------------------------------------------------------------------
# This configuration file is a simple Bash script that declares variables
# defining user settings for SyncDroid. Upon execution, the SyncDroid script
# will source this file, loading the values into its environment. 
# Users can modify the variable values below to customise their sync settings.
# Ensure that variable names remain unchanged and only the values after the '='
# are edited. These settings will be treated as constants once loaded.
# ------------------------------------------------------------------------------
# OffsiteRemoteName         Name of offsite rclone remote.
# OnsiteRemoteName          Name of onsite rclone remote.
# SSHPrivateKeyPath         Path to private key file.
# DevRootPath               Android device root directory path.
# DirSyncListPath           Path to file containing list of directories to sync.
# OffsiteRemotePath         Path to use on the offsite remote.
# OnsiteRemotePath          Path to use on the onsite remote.
# OnsiteConnectionTestPort  Port of machine hosting onsite rclone remote.
# OnsiteConnectionTestURL   URL of machine hosting onsite rclone remote.
# OffsiteConnectionTestURL  URL of any website to test internet connection.
# ConnectionTestPackets     Number of packets to use during connection test.
# ConnectionTestTimeout     Max number of seconds to wait for connection test.
# ------------------------------------------------------------------------------
# EXAMPLES:
# OffsiteRemoteName="CryptGDrive"
# OnsiteRemoteName="CryptCastor"
# SSHPrivateKeyPath="${HOME}/.ssh/id_ed25519"
# DevRootPath="/storage/emulated/0"
# DirSyncListPath="${HOME}/.config/syncdroid/dirsynclist.txt"
# OffsiteRemotePath="ENCRYPTED/Android_Backup"
# OnsiteRemotePath="/media/Backup_HDD/RCLONE/ENCRYPTED/Android_Backup"
# OnsiteConnectionTestPort="22"
# OnsiteConnectionTestURL="Raymond.local"
# OffsiteConnectionTestURL="www.google.com"
# ConnectionTestPackets="4"
# ConnectionTestTimeout="5"
# ------------------------------------------------------------------------------
# NAMES
OffsiteRemoteName="GDrive_Crypt" # Wraps 'GDrive:ENCRYPTED_RCLONE_REMOTE'
OnsiteRemoteName="Raymond_Crypt" # Wraps 'Raymond:/media/Castor/RCLONE/ENCRYPTED'

# PATHS
SSHPrivateKeyPath="" # Leave this blank if a private key is not used
DevRootPath="/storage/emulated/0"
DirSyncListPath="${HOME}/.config/syncdroid/directory_sync_list.txt"
OffsiteRemotePath="Rohan_S23_Backup"
OnsiteRemotePath="Rohan_S23_Backup"

# ADDRESSES
OnsiteConnectionTestPort="22"
OnsiteConnectionTestURL="Raymond.local"
OffsiteConnectionTestURL="www.google.com"

# OTHER
ConnectionTestPackets="4"
ConnectionTestTimeout="5"
################################################################################