sudo mkdir -p /etc/greetd

# Install greetd configs and set up autologin
omarchy-greeter regreet --autologin

# Disable conflicting display managers
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl disable gdm.service 2>/dev/null || true
sudo systemctl disable lightdm.service 2>/dev/null || true

sudo systemctl enable greetd.service
