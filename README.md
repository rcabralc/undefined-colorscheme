Undefined color scheme
======================

A color scheme with dark and light variants, generated with ERB and Ruby.
Example for a NeoVim color scheme (execute in the project root):

```sh
$ mkdir -p ~/.config/nvim/colors
$ erb -r ./undefined.rb vim.vim.erb > ~/.config/nvim/colors/undefined.vim
```
