#!/bin/bash
#
# Samba Setup Automation Script for Cybersecurity Competition
# For Rocky Linux 8 / RHEL-based distributions
#

# Exit on any error
set -e

# Text colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

# Configuration Variables - DO NOT MODIFY
SAMBA_SHARE_PATH="/srv/samba/secure"
WORKGROUP="WORKGROUP"
SERVER_NAME="TEAM12-SMB"
SAMBA_GROUP="sambausers"
SCORING_DIR="/mnt/files"

# Scoring Users
SAMBA_USERS=(
    "benjamin_franklin"
    "alexander_hamilton"
    "john_adams"
    "theodore_roosevelt"
    "franklin_d"
    "winston_churchill"
    "florence_nightingale"
    "eleanor_roosevelt"
    "mother_teresa"
    "mahatma_gandhi"
    "socrates"
    "plato"
    "aristotle"
    "hippocrates"
    "archimedes"
    "rene_descartes"
    "voltaire"
    "jean_jacques_rousseau"
    "immanuel_kant"
    "friedrich_nietzsche"
    "sigmund_freud"
    "charles_darwin"
    "marie_antoinette"
    "louis_xiv"
    "peter_the_great"
)

# Scoring Files
SCORING_FILES=(
    "amsterdam.data"
    "berlin.data"
    "brussels.data"
    "data_dump_1.bin"
    "data_dump_2.bin"
    "data_dump_3.bin"
    "datadump.bin"
    "dublin.data"
    "lisbon.data"
    "ljubljana.data"
    "nicosia.data"
    "oslo.data"
    "paris.data"
    "prague.data"
    "reykjavik.data"
    "rome.data"
    "stockholm.data"
    "valletta.data"
    "vilnius.data"
    "warsaw.data"
)

# User password hash
USER_PASSWORD_HASH='$6$KHk2hJlrIZKWxWA9$z2OrpVg05wxoUp/BL12VY9rvxvgyZhta.qKf9SwckeNMcW4QvCJACSA4QyBwy88UpPAGDrskbu7rb7sh8fbnM1'

# Function to check if package is installed
is_installed() {
    if rpm -q "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to find files on the system
find_and_link_files() {
    local target_dir="$1"
    local found_files=()
    local missing_files=()
    
    log_info "Searching for scoring files..."
    
    # First check the scoring directory if it exists
    if [ -d "$SCORING_DIR" ]; then
        log_info "Checking scoring directory: $SCORING_DIR"
        for file in "${SCORING_FILES[@]}"; do
            if [ -f "$SCORING_DIR/$file" ]; then
                log_info "Found file $file in $SCORING_DIR"
                found_files+=("$SCORING_DIR/$file")
            else
                missing_files+=("$file")
            fi
        done
    else
        log_warn "Scoring directory $SCORING_DIR not found"
        missing_files=("${SCORING_FILES[@]}")
    fi
    
    # If files are still missing, search the entire system
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_info "Searching the system for missing files..."
        for file in "${missing_files[@]}"; do
            log_info "Searching for $file..."
            found=$(find / -name "$file" -type f 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                log_info "Found $file at $found"
                found_files+=("$found")
            else
                log_warn "Could not find $file anywhere on the system"
            fi
        done
    fi
    
    # Create links to all found files in the target directory
    for src in "${found_files[@]}"; do
        file=$(basename "$src")
        if [ ! -f "$target_dir/$file" ]; then
            ln -s "$src" "$target_dir/$file"
            log_info "Created symbolic link for $file"
        else
            log_info "File $file already exists in $target_dir"
        fi
    done
    
    # Return number of files found
    echo ${#found_files[@]}
}

# Step 1: Install Samba and dependencies
log_info "Step 1: Installing Samba and dependencies..."
dnf update -y
for pkg in samba samba-common samba-client policycoreutils-python-utils iptables-services; do
    if ! is_installed "$pkg"; then
        dnf install -y "$pkg"
        log_info "Installed $pkg"
    else
        log_info "$pkg already installed"
    fi
done

# Step 2: Configure firewall
log_info "Step 2: Configuring firewall..."
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --permanent --add-port=445/tcp
    firewall-cmd --reload
    log_info "Firewall configured using firewalld"
else
    log_info "Creating iptables rules..."
    
    # Create iptables rules file
    cat > /etc/iptables-samba.rules << EOF
# Secure iptables configuration for SSH and Samba
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow established and related connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback interface
-A INPUT -i lo -j ACCEPT

# Allow SSH with rate limiting
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT

# Allow Samba (SMB)
-A INPUT -p tcp --dport 445 -j ACCEPT

# Block invalid packets
-A INPUT -m conntrack --ctstate INVALID -j DROP

# Log and drop other traffic
-A INPUT -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
-A INPUT -j DROP
COMMIT
EOF

    # Apply iptables rules
    iptables-restore < /etc/iptables-samba.rules
    service iptables save
    systemctl enable iptables
    log_info "Firewall configured using iptables"
fi

# Step 3: Create directory structure
log_info "Step 3: Creating directory structure..."
mkdir -p "$SAMBA_SHARE_PATH"
chmod 0770 "$SAMBA_SHARE_PATH"

# Step 4: Configure SELinux
log_info "Step 4: Configuring SELinux..."
semanage fcontext -a -t samba_share_t "${SAMBA_SHARE_PATH}(/.*)?"
restorecon -Rv "$SAMBA_SHARE_PATH"
setsebool -P samba_enable_home_dirs on
setsebool -P samba_export_all_ro=on samba_export_all_rw=on
log_info "SELinux configured for Samba"

# Step 5: Create group and manage users
log_info "Step 5: Managing users and groups..."

# Create Samba group if it doesn't exist
if ! getent group "$SAMBA_GROUP" >/dev/null; then
    groupadd "$SAMBA_GROUP"
    log_info "Created group $SAMBA_GROUP"
else
    log_info "Group $SAMBA_GROUP already exists"
fi

# Process users
for username in "${SAMBA_USERS[@]}"; do
    # Check if user exists
    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
        # Check if the password hash matches the required hash
        current_hash=$(grep "^$username:" /etc/shadow | cut -d: -f2)
        if [ "$current_hash" != "$USER_PASSWORD_HASH" ]; then
            log_warn "Password hash for $username doesn't match required hash, updating..."
            usermod -p "$USER_PASSWORD_HASH" "$username"
            log_info "Updated password hash for $username"
        else
            log_info "Password hash for $username already matches required hash"
        fi
    else
        useradd -m "$username"
        # Use the password hash for all users
        usermod -p "$USER_PASSWORD_HASH" "$username"
        log_info "Created user $username with specified password hash"
    fi
    
    # Add user to Samba group
    if groups "$username" | grep -q "$SAMBA_GROUP"; then
        log_info "User $username is already in group $SAMBA_GROUP"
    else
        usermod -aG "$SAMBA_GROUP" "$username"
        log_info "Added user $username to group $SAMBA_GROUP"
    fi
    
    # Add user to Samba password database if not already there
    if ! pdbedit -L | grep -q "^$username:"; then
        (echo "Temp123!"; echo "Temp123!") | smbpasswd -a "$username"
        log_info "Added user $username to Samba password database"
    else
        log_info "User $username already in Samba password database"
    fi
done

# Step 6: Create Samba configuration
log_info "Step 6: Creating Samba configuration..."
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)

cat > /etc/samba/smb.conf << EOF
[global]
    workgroup = WORKGROUP
    server string = Team 12 Samba Server
    netbios name = TEAM12-SMB
    server role = standalone server
    
    # Security settings - using the stronger options
    security = user
    passdb backend = tdbsam
    map to guest = Bad User
    encrypt passwords = yes
    
    # Protocol settings - using the stronger SMB3_11
    server min protocol = SMB3_11
    server smb encrypt = required
    server signing = mandatory
    server smb3 encryption algorithms = AES-128-GCM, AES-128-CCM, AES-256-GCM, AES-256-CCM
    server smb3 signing algorithms = AES-128-GMAC
    
    client min protocol = SMB3_11
    client smb encrypt = required
    client signing = required
    client ipc signing = required
    client protection = encrypt
    client smb3 encryption algorithms = AES-128-GCM, AES-128-CCM, AES-256-GCM, AES-256-CCM
    client smb3 signing algorithms = AES-128-GMAC
    
    # Session timeout (shorter is more secure)
    deadtime = 5
    
    # Network access controls
    hosts allow = 127.0.0.1 192.168.12.0/24 172.18.0.0/16
    hosts deny = 0.0.0.0/0
    
    # Disable guest access
    restrict anonymous = 2
    
    # Disable print services
    printing = bsd
    printcap name = /dev/null
    load printers = no
    disable spoolss = yes
    
    # Logging
    log file = /var/log/samba/log.%m
    max log size = 0
    log level = 0 vfs:10

[SecureShare]
    comment = Secure Competition Share
    path = $SAMBA_SHARE_PATH
    browseable = yes
    read only = no
    guest ok = no
    valid users = @$SAMBA_GROUP
    create mask = 0660
    directory mask = 0770
    force create mode = 0660
    force directory mode = 0770
EOF

# Test configuration
testparm -s

# Step 7: Set ownership of share directory
log_info "Step 7: Setting ownership of share directory..."
chown -R root:"$SAMBA_GROUP" "$SAMBA_SHARE_PATH"

# Step 8: Find and link required files
log_info "Step 8: Finding and linking required files..."
files_found=$(find_and_link_files "$SAMBA_SHARE_PATH")
log_info "Found and linked $files_found of ${#SCORING_FILES[@]} required files"

# Step 9: Set permissions on linked files
log_info "Step 9: Setting permissions on linked files..."
chmod -R 0660 "$SAMBA_SHARE_PATH"/*
chown -R root:"$SAMBA_GROUP" "$SAMBA_SHARE_PATH"/*

# Step 10: Enable and start Samba services
log_info "Step 10: Starting Samba services..."
systemctl enable smb nmb
systemctl restart smb nmb

# Verify services are running
if systemctl is-active --quiet smb && systemctl is-active --quiet nmb; then
    log_info "Samba services started successfully!"
else
    log_error "Failed to start Samba services. Check logs with: systemctl status smb nmb"
    exit 1
fi

# Final verification
log_info "Testing Samba configuration..."
# Use authentication for the test (one of the scoring users)
smbclient -L localhost -U "${SAMBA_USERS[0]}"%Temp123!

log_info "==================================================="
log_info "Samba setup complete! Your configuration is ready."
log_info "Share name: SecureShare"
log_info "Share path: $SAMBA_SHARE_PATH"
log_info "Users configured: ${#SAMBA_USERS[@]} scoring users"
log_info "Files found and linked: $files_found"
log_info "==================================================="
log_info "To test, run: smbclient //localhost/SecureShare -U ${SAMBA_USERS[0]}"
log_info "Default Samba password for users: Temp123!"

# Secure the rc directories
log_info "Securing rc directories against tampering..."
for dir in /etc/rc.d/rc{0,1,2,3,4,5,6}.d /etc/rc.d/init.d; do
    if [ -d "$dir" ]; then
        chattr +i "$dir"
        log_info "Made $dir immutable"
    fi
done

log_info "Setup complete! Samba service is now configured securely."
exit 0
