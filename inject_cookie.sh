#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# Roblox Cookie Injector for Termux (Android)
# Injects .ROBLOSECURITY cookie into com.roblox.client
# Automatically launches Roblox after injection
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║       Roblox Cookie Injector for Termux      ║"
echo "║         Target: com.roblox.client            ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# --- Configuration ---
# Try common Roblox package names
PACKAGE_CANDIDATES=(
    "com.roblox.client"
    "com.roblox"
)

ROBLOX_PACKAGE=""
ROBLOX_DATA_DIR=""
COOKIE_FILE=""
SHARED_PREFS_DIR=""
COOKIE_PREFS_FILE=""

# --- Helper Functions ---

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[*]${NC} $1"
}

# --- Check if running as root ---
check_root() {
    print_step "Checking root permissions..."
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script requires root permissions!"
        print_error "Please run: su -c 'bash $0'"
        echo ""
        echo -e "${YELLOW}Alternative: Use 'sudo' if available:${NC}"
        echo "  sudo bash $0"
        exit 1
    fi
    print_info "Root access confirmed."
}

# --- Detect Roblox package ---
detect_package() {
    print_step "Detecting Roblox package name..."
    for pkg in "${PACKAGE_CANDIDATES[@]}"; do
        if [ -d "/data/data/${pkg}" ]; then
            ROBLOX_PACKAGE="$pkg"
            ROBLOX_DATA_DIR="/data/data/${pkg}"
            COOKIE_FILE="${ROBLOX_DATA_DIR}/files/RobloxCookies.dat"
            SHARED_PREFS_DIR="${ROBLOX_DATA_DIR}/shared_prefs"
            COOKIE_PREFS_FILE="${SHARED_PREFS_DIR}/RobloxPreferences.xml"
            print_info "Found Roblox package: ${ROBLOX_PACKAGE}"
            return 0
        fi
    done

    print_error "Roblox data directory not found!"
    print_error "Checked: ${PACKAGE_CANDIDATES[*]}"
    print_error "Make sure Roblox is installed on your device."
    exit 1
}

# --- Stop Roblox if running ---
stop_roblox() {
    print_step "Stopping Roblox process (if running)..."
    am force-stop "$ROBLOX_PACKAGE" 2>/dev/null
    sleep 2
    print_info "Roblox process stopped."
}

# --- Backup existing cookie ---
backup_cookie() {
    print_step "Backing up existing cookie (if any)..."
    if [ -f "$COOKIE_FILE" ]; then
        BACKUP_FILE="${COOKIE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$COOKIE_FILE" "$BACKUP_FILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_info "Backup created: ${BACKUP_FILE}"
        else
            print_warn "Could not create backup."
        fi
    else
        print_info "No existing cookie file found. Nothing to backup."
    fi
}

# --- Inject cookie into RobloxCookies.dat ---
inject_cookie_dat() {
    local cookie="$1"
    print_step "Injecting cookie into ${COOKIE_FILE}..."

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$COOKIE_FILE")" 2>/dev/null

    # Write the cookie to the file
    echo -n "$cookie" > "$COOKIE_FILE" 2>/dev/null

    if [ $? -eq 0 ]; then
        print_info "Cookie written to ${COOKIE_FILE}"
        # Set proper permissions
        chmod 600 "$COOKIE_FILE" 2>/dev/null
        chown "$ROBLOX_PACKAGE:$ROBLOX_PACKAGE" "$COOKIE_FILE" 2>/dev/null
        print_info "Permissions set on cookie file."
    else
        print_error "Failed to write cookie to ${COOKIE_FILE}"
        exit 1
    fi
}

# --- Inject cookie into SharedPreferences XML ---
inject_cookie_xml() {
    local cookie="$1"
    print_step "Injecting cookie into SharedPreferences..."

    mkdir -p "$SHARED_PREFS_DIR" 2>/dev/null

    # Create or update the XML preferences file
    if [ -f "$COOKIE_PREFS_FILE" ]; then
        # File exists — try to update the cookie entry
        if grep -q '"ROBLOSECURITY"' "$COOKIE_PREFS_FILE" 2>/dev/null; then
            sed -i "s|<string name=\"ROBLOSECURITY\">.*</string>|<string name=\"ROBLOSECURITY\">$cookie</string>|" "$COOKIE_PREFS_FILE" 2>/dev/null
            print_info "Updated existing ROBLOSECURITY entry in SharedPreferences."
        else
            # Insert before closing </map> tag
            sed -i "s|</map>|    <string name=\"ROBLOSECURITY\">$cookie</string>\n</map>|" "$COOKIE_PREFS_FILE" 2>/dev/null
            print_info "Added ROBLOSECURITY entry to SharedPreferences."
        fi
    else
        # Create new XML file
        cat > "$COOKIE_PREFS_FILE" << EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="ROBLOSECURITY">$cookie</string>
</map>
EOF
        print_info "Created new SharedPreferences file with cookie."
    fi

    # Set proper permissions
    chmod 600 "$COOKIE_PREFS_FILE" 2>/dev/null
    chown "$ROBLOX_PACKAGE:$ROBLOX_PACKAGE" "$COOKIE_PREFS_FILE" 2>/dev/null
    chmod 700 "$SHARED_PREFS_DIR" 2>/dev/null
    chown "$ROBLOX_PACKAGE:$ROBLOX_PACKAGE" "$SHARED_PREFS_DIR" 2>/dev/null
}

# --- Launch Roblox ---
launch_roblox() {
    print_step "Launching Roblox to apply cookie..."
    
    # Try to get the main activity
    MAIN_ACTIVITY=$(cmd package resolve-activity --brief "$ROBLOX_PACKAGE" 2>/dev/null | tail -1)
    
    if [ -n "$MAIN_ACTIVITY" ]; then
        print_info "Starting activity: ${MAIN_ACTIVITY}"
        am start -n "$MAIN_ACTIVITY" 2>/dev/null
    else
        print_info "Starting package directly..."
        am start -n "${ROBLOX_PACKAGE}/.app.MainActivity" 2>/dev/null || \
        am start -n "${ROBLOX_PACKAGE}/com.roblox.client.startup.SplashActivity" 2>/dev/null || \
        monkey -p "$ROBLOX_PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        print_info "Roblox launched successfully!"
    else
        print_warn "Could not launch Roblox automatically. Please open it manually."
    fi
}

# --- Verify injection ---
verify_injection() {
    print_step "Verifying cookie injection..."
    local success=true

    if [ -f "$COOKIE_FILE" ]; then
        local file_size=$(stat -c%s "$COOKIE_FILE" 2>/dev/null || wc -c < "$COOKIE_FILE" 2>/dev/null)
        if [ "$file_size" -gt 0 ]; then
            print_info "Cookie file exists and is not empty (${file_size} bytes)."
        else
            print_warn "Cookie file exists but is empty."
            success=false
        fi
    else
        print_warn "Cookie file not found at ${COOKIE_FILE}"
        success=false
    fi

    if [ -f "$COOKIE_PREFS_FILE" ]; then
        if grep -q "ROBLOSECURITY" "$COOKIE_PREFS_FILE" 2>/dev/null; then
            print_info "ROBLOSECURITY entry found in SharedPreferences."
        else
            print_warn "ROBLOSECURITY entry not found in SharedPreferences."
            success=false
        fi
    else
        print_warn "SharedPreferences file not found."
        success=false
    fi

    if [ "$success" = true ]; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║       Cookie injection completed!            ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
    else
        print_warn "Some checks failed. Cookie may not be fully injected."
    fi
}

# --- Main Execution ---

main() {
    local cookie=""

    # Check for cookie argument
    if [ $# -ge 1 ]; then
        cookie="$1"
    else
        # Prompt for cookie
        echo ""
        echo -e "${YELLOW}Enter your .ROBLOSECURITY cookie:${NC}"
        read -r cookie
        echo ""
    fi

    # Validate cookie
    if [ -z "$cookie" ]; then
        print_error "No cookie provided. Exiting."
        exit 1
    fi

    # Check if it looks like a Roblox cookie (starts with _|WARNING:-DO_NOT_SHARE)
    if [[ "$cookie" == _\|WARNING* ]]; then
        print_info "Cookie format looks valid (contains security warning)."
    else
        print_warn "Cookie does not start with '_|WARNING...' — it may not be a valid .ROBLOSECURITY cookie."
        echo -e "${YELLOW}Proceed anyway? (y/N):${NC}"
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_info "Aborted by user."
            exit 0
        fi
    fi

    echo ""
    print_step "Starting cookie injection process..."
    echo ""

    check_root
    detect_package
    stop_roblox
    backup_cookie
    inject_cookie_dat "$cookie"
    inject_cookie_xml "$cookie"
    verify_injection
    launch_roblox

    echo ""
    print_info "Script finished. Roblox should now be opening with your cookie injected."
    echo ""
}

# Run main with all arguments
main "$@"
