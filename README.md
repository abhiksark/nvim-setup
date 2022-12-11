# nvim-setup

Installation 

brew install neovim

sudo apt install neovim


mkdir ~/.config/nvim

touch ~/.config/nvim/init.vim

curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

mkdir ~/.config/nvim/vim-plug

touch ~/.config/nvim/vim-plug/plugins.vim

echo "source $HOME/.config/nvim/vim-plug/plugins.vim">>init.vim

