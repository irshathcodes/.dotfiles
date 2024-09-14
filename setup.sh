#!/usr/bin/bash

rm -rf ~/.bashrc ~/.bash_aliases ~/.gitconfig

ln -s ~/.dotfiles/.bashrc ~/.bashrc
ln -s ~/.dotfiles/.bash_aliases ~/.bash_aliases
ln -s ~/.dotfiles/.gitconfig ~/.gitconfig
ln -s ~/.dotfiles/.wezterm.lua ~/.wezterm.lua

rm -rf ~/.config/nvim
mkdir ~/.config/nvim
ln -s ~/.dotfiles/.init.lua ~/.config/nvim/init.lua





