CONFIG SOURCES

Populate ./config from the Mac whose current configuration you want to preserve.

From the Mac:

cd ~/Documents/bootstrap-new-mac
mkdir -p config

cp ~/.bash_profile config/bash_profile
cp ~/.bashrc config/bashrc
cp ~/.shell-tools config/shell-tools
cp ~/.config/starship.toml config/starship.toml
cp "$HOME/Library/Application Support/com.mitchellh.ghostty/config" config/ghostty-config

The bootstrap script copies these files to their target locations.
It does not generate their contents.
