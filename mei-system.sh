#!/bin/sh

# ==============================================================================
# LARBS (Void Musl Port) - Luke's Auto-Rice Bootstrapping Script
# Re-engineered for Void Linux (specifically musl libc) by Mei
# ==============================================================================

set -e

DOTFILES_REPO="https://github.com/LukeSmithxyz/voidrice.git"
PROGS_FILE="progs.csv"
REPONAME="voidrice"

# Color helpers
green() { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    red "Error: Do not run this script as root directly. Run it as your regular user (with sudo access)."
    exit 1
fi

if ! command -v xbps-install >/dev/null 2>&1; then
    red "Error: xbps-install not found. This script requires Void Linux."
    exit 1
fi

if [ ! -f "$PROGS_FILE" ]; then
    red "Error: $PROGS_FILE not found in the current directory."
    exit 1
fi

sudo -v
# Keep sudo alive in background during long builds
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

yellow "Initializing Void Linux (musl) bootstrapping setup..."

# ------------------------------------------------------------------------------
# 1. System Sync & Non-Free Repositories
# ------------------------------------------------------------------------------
yellow "Synchronizing system repositories and enabling non-free..."
sudo xbps-install -Syu
sudo xbps-install -Sy void-repo-nonfree
sudo xbps-install -Syu

# ------------------------------------------------------------------------------
# 2. Package Installation Loop
# ------------------------------------------------------------------------------
yellow "Installing packages from $PROGS_FILE..."

while IFS=',' read -r tag pkg desc; do
    # Skip comments and empty lines
    case "$tag" in
        \#*|"") continue ;;
    esac

    # Standard XBPS Package
    if [ -z "$tag" ]; then
        yellow "Installing: $pkg ($desc)..."
        sudo xbps-install -y "$pkg" || true

    # Git Repository Source Build (Suckless tools / dwmblocks)
    elif [ "$tag" = "G" ]; then
        yellow "Building git source: $pkg ($desc)..."
        dir_name=$(basename "$pkg" .git)
        target_dir="$HOME/.local/src/$dir_name"

        mkdir -p "$HOME/.local/src"
        if [ -d "$target_dir" ]; then
            rm -rf "$target_dir"
        fi

        git clone "$pkg" "$target_dir"
        cd "$target_dir"
        make
        sudo make install
        cd - >/dev/null
    fi
done < "$PROGS_FILE"

# ------------------------------------------------------------------------------
# 3. Deploy Dotfiles (Luke Smith's voidrice)
# ------------------------------------------------------------------------------
yellow "Deploying dotfiles from $DOTFILES_REPO..."

mkdir -p "$HOME/.config"
temp_dots=$(mktemp -d)

git clone --recursive "$DOTFILES_REPO" "$temp_dots/$REPONAME"
cp -rf "$temp_dots/$REPONAME/." "$HOME/"
rm -rf "$temp_dots"

# Ensure script execution permissions in ~/.local/bin
if [ -d "$HOME/.local/bin" ]; then
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Runit System Services & Audio Infrastructure
# ------------------------------------------------------------------------------
yellow "Enabling required system daemons via runit..."

# Ensure core service packages are present
sudo xbps-install -y dbus NetworkManager elogind bluez pipewire wireplumber alsa-pipewire

# 4.1 Enable D-Bus (Foundation for all desktop IPC)
if [ ! -L /var/service/dbus ]; then
    sudo ln -s /etc/sv/dbus /var/service/
fi

# 4.2 Enable NetworkManager (Disables default dhcpcd if running)
if [ ! -L /var/service/NetworkManager ]; then
    sudo rm -f /var/service/dhcpcd /var/service/wpa_supplicant 2>/dev/null || true
    sudo ln -s /etc/sv/NetworkManager /var/service/
fi

# 4.3 Enable Elogind (Handles user seat permissions, poweroff, suspend without root)
if [ ! -L /var/service/elogind ]; then
    sudo ln -s /etc/sv/elogind /var/service/
fi

# 4.4 Enable Bluetooth Daemon
if [ ! -L /var/service/bluetoothd ]; then
    sudo ln -s /etc/sv/bluetoothd /var/service/
fi

# 4.5 PipeWire System Integration (Hooks WirePlumber & PipeWire-Pulse directly)
yellow "Configuring PipeWire audio hooks..."
sudo mkdir -p /etc/pipewire/pipewire.conf.d
sudo ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
sudo ln -sf /usr/share/examples/wireplumber/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/ 2>/dev/null || \
sudo ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/

# 4.51 Enable ALSA routing through PipeWire
sudo mkdir -p /etc/alsa/conf.d
sudo ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/
sudo ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/

# 4.6 Add user to audio, video, and network groups
yellow "Configuring user group permissions..."
sudo usermod -aG audio,video,network,input,wheel "$USER"

# 4.7 Enable Flatpak runtime
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# ------------------------------------------------------------------------------
# 5. Default Shell Configuration
# ------------------------------------------------------------------------------
if [ "$SHELL" != "$(which zsh)" ]; then
    yellow "Changing default shell to zsh..."
    sudo chsh -s "$(which zsh)" "$USER"
fi

# ------------------------------------------------------------------------------
# 6. Generate Clean .xinitrc for dwm
# ------------------------------------------------------------------------------
cat << 'EOF' > "$HOME/.xinitrc"
#!/bin/sh

# Set up environment variables for musl/POSIX
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH="$HOME/.local/bin:$PATH"

# PipeWire session startup (WirePlumber & Pulse interfaces spawn automatically via hooks)
pipewire &

# Autostart dwmblocks
dwmblocks &

# Set wallpaper if xwallpaper is configured
if command -v xwallpaper >/dev/null 2>&1 && [ -f "$HOME/Pictures/wallpapers/Neon Genesis Evangelion/eva02.jpg" ]; then
    xwallpaper --zoom "$HOME/Pictures/wallpapers/Neon Genesis Evangelion/eva02.jpg" &
fi

# Launch dwm inside unified dbus session
exec dbus-run-session dwm
EOF

chmod +x "$HOME/.xinitrc"

green "=========================================================================="
green "Bootstrap complete! System ready on Void Musl."
green "Type 'startx' after logging in to launch dwm."
green "=========================================================================="