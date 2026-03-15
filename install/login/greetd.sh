sudo mkdir -p /etc/greetd

# Install greetd configs and set up autologin
omarchy-greeter regreet --autologin

# Keep Plymouth splash image on framebuffer after daemon exits
sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d
sudo cp "$OMARCHY_PATH/config/greetd/plymouth-quit-retain-splash.conf" /etc/systemd/system/plymouth-quit.service.d/
sudo systemctl daemon-reload

# Disable conflicting display managers
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl disable gdm.service 2>/dev/null || true
sudo systemctl disable lightdm.service 2>/dev/null || true

sudo systemctl enable greetd.service
