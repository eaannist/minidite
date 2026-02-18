# minidite

```
                                              ;                                  
                                              ED.                                
                           L.                 E#Wi                             ,;
                       t   EW:        ,ft t   E###G.       t                 f#i 
            ..       : Ej  E##;       t#E Ej  E#fD#W;      Ej GEEEEEEEL    .E#t  
           ,W,     .Et E#, E###t      t#E E#, E#t t##L     E#,,;;L#K;;.   i#W,   
          t##,    ,W#t E#t E#fE#f     t#E E#t E#t  .E#K,   E#t   t#E     L#D.    
         L###,   j###t E#t E#t D#G    t#E E#t E#t    j##f  E#t   t#E   :K#Wfff;  
       .E#j##,  G#fE#t E#t E#t  f#E.  t#E E#t E#t    :E#K: E#t   t#E   i##WLLLLt 
      ;WW; ##,:K#i E#t E#t E#t   t#K: t#E E#t E#t   t##L   E#t   t#E    .E#L     
     j#E.  ##f#W,  E#t E#t E#t    ;#W,t#E E#t E#t .D#W;    E#t   t#E      f#E:   
   .D#L    ###K:   E#t E#t E#t     :K#D#E E#t E#tiW#G.     E#t   t#E       ,WW;   
  :K#t     ##D.    E#t E#t E#t      .E##E E#t E#K##i       E#t   t#E        .D#; 
  ...      #G      ..  E#t ..         G#E E#t E##D.        E#t    fE          tt 
           j           ,;.             fE ,;. E#t          ,;.     :             
                                        ,     L:                                 
```

Minimal Arch Linux server: interactive install and setup. Optimized for SSH and remote work.

## Features

- **install.sh** (from Arch ISO, root): single disk, EFI 256MiB + root; base + openssh, sudo, git, zsh, NetworkManager, grub. Interactive: disk, hostname, user, password, locale, timezone.
- **setup.sh** (after first login, user): extra packages (micro, btop, zoxide, fzf, eza, bat, tmux, Nerd Font); Oh My Posh + custom theme; .zshrc and .tmux.conf; interactive SSH key generation and authorized_keys.

## Quick start

```bash
# 1. Install (Arch ISO, root)
curl -fsSL https://pages.acridite.cc/minidite/install | bash

# 2. Reboot, then (as user)
curl -fsSL https://pages.acridite.cc/minidite/setup | bash
exec zsh
```

## Links

- **Bootstrap:** https://pages.acridite.cc/minidite/install and https://pages.acridite.cc/minidite/setup
- **Repo:** https://github.com/eaannist/minidite

MIT.
