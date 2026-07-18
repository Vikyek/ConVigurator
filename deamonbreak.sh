sudo find /etc/systemd/system/ -xtype l -print -delete | grep . || echo "No broken symlinks found."
