#!/usr/bin/bash

# Clone the repo and download my dotfiles
rm -rf ~/.bashrc ~/.bash_aliases

ln -s ~/.dotfiles/.bashrc ~/.bashrc
ln -s ~/.dotfiles/.bash_aliases ~/.bash_aliases
ln -s ~/.dotfiles/.gitconfig ~/.gitconfig
ln -s ~/.dotfiles/.wezterm.lua ~/.wezterm.lua

