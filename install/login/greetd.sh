sudo mkdir -p /etc/greetd

# Install greetd configs and set up autologin
omarchy-greeter tuigreet --autologin
sudo cp "$OMARCHY_PATH/config/greetd/regreet.toml" /etc/greetd/regreet.toml

# Keep Plymouth splash visible until Hyprland takes over the display
sudo mkdir -p /etc/systemd/system/greetd.service.d
sudo cp "$OMARCHY_PATH/config/greetd/no-wait-plymouth.conf" /etc/systemd/system/greetd.service.d/

sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d
sudo cp "$OMARCHY_PATH/config/greetd/delay-for-compositor.conf" /etc/systemd/system/plymouth-quit.service.d/

sudo systemctl daemon-reload

# Disable conflicting display managers
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl disable gdm.service 2>/dev/null || true
sudo systemctl disable lightdm.service 2>/dev/null || true

sudo systemctl enable greetd.service
