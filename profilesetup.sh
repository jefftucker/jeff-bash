#!/bin/bash

if [ ! -d $HOME/.vim/autoload ]; then
    # install pathogen and vim stuff
    mkdir -p ~/.vim/autoload ~/.vim/bundle && \
    curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
    if [ ! -f $HOME/.vimrc ]; then
        touch $HOME/.vimrc
    fi
else
    echo "autoload directory found"
fi

# ensure pathogen is set to start up in .vimrc
grep pathogen $HOME/.vimrc
if [ "$?" -eq "1" ]; then
    cp $HOME/.vimrc /tmp/vimrctemp
    echo "execute pathogen#infect()" > $HOME/.vimrc
    cat /tmp/vimrctemp >> $HOME/.vimrc
fi

# vim plugins
if [ ! -d $HOME/.vim/bundle/vim-sensible ]; then
    cd ~/.vim/bundle && \
    git clone https://github.com/tpope/vim-sensible.git
fi

if [ ! -d $HOME/.vim/bundle/vim-colors-solarized ]; then
    cd ~/.vim/bundle
    git clone git://github.com/altercation/vim-colors-solarized.git
fi

if [ ! -d $HOME/.vim/bundle/jeff-vim ]; then
    cd ~/.vim/bundle
    git clone https://github.com/jefftucker/jeff-vim.git
fi
