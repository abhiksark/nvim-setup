# nvim-setup

Installation 

brew install neovim

sudo apt install neovim


sudo apt install zsh




sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"


git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc


mkdir ~/.config/nvim

touch ~/.config/nvim/init.vim

curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

mkdir ~/.config/nvim/vim-plug

touch ~/.config/nvim/vim-plug/plugins.vim

echo "source $HOME/.config/nvim/vim-plug/plugins.vim">>init.vim

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions



