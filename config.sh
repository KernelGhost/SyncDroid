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
# ParentDirName            Name of folder on rclone remote containing sync.
# OnlineRemoteName         Name of online rclone remote.
# LocalRemoteName          Name of local rclone remote.
# DevRootPath              Android device root directory path.
# DirSyncListPath          Path to file containing list of directories to sync.
# LocalConnectionTestURL   URL of machine hosting local rclone remote.
# OnlineConnectionTestURL  URL of any website to test internet connection.
# ConnectionTestPackets    Number of packets to use during connection test.
# ConnectionTestTimeout    Max number of seconds to wait for connection test.
# ------------------------------------------------------------------------------
# EXAMPLES:
# ParentDirName="Phone_Backup"
# OnlineRemoteName="CryptGDrive"
# LocalRemoteName="CryptCastor"
# DevRootPath="/storage/emulated/0"
# DirSyncListPath="${HOME}/.config/syncdroid/dirsynclist.txt"
# LocalConnectionTestURL="Raymond.local"
# OnlineConnectionTestURL="www.google.com"
# ConnectionTestPackets="4"
# ConnectionTestTimeout="5"
# ------------------------------------------------------------------------------
# NAMES
ParentDirName="Phone_Backup"
OnlineRemoteName="CryptGDrive"
LocalRemoteName="CryptCastor"

# PATHS
DevRootPath="/storage/emulated/0"
DirSyncListPath="${HOME}/.config/syncdroid/directory_sync_list.txt"

# ADDRESSES
LocalConnectionTestURL="Raymond.local"
OnlineConnectionTestURL="www.google.com"

# OTHER
ConnectionTestPackets="4"
ConnectionTestTimeout="5"
################################################################################