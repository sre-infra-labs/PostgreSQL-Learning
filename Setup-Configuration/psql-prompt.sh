$ sudo -i -u postgres
$ sudo -u postgres
$ sudo su - postgres

# Update bash shell prompt for Postgres user on ubuntu
    # Add following lines in postgres user's ~/.bashrc file
    ---------------------------------------------------------
    # Define colors
    GREEN='\[\033[32m\]'
    RED='\[\033[31m\]'
    YELLOW='\[\033[33m\]'
    BLUE='\[\033[34m\]'
    RESET='\[\033[0m\]'

    # Define a newline
    NEWLINE='\n'

    # Custom prompt
    PS1="----- ${GREEN}[\$(date +'%Y-%b-%d %H:%M:%S')]${RESET} ${RED}\u${RESET}@${YELLOW}\h${RESET} ${BLUE}(\$(pwd | sed -e 's|.*/||'))${RESET}${NEWLINE}|------------\$ "

    unset color_prompt force_color_prompt
    ---------------------------------------------------------

# postgres user uses Login Shell.
    # So manually source ~/.bashrc in ~/.profile
    # Add the following to ~/.profile:

    ---------------------------------------------------------
    # Source .bashrc if it exists
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
    ---------------------------------------------------------

# Update psql prompt to include host name
    # https://gist.github.com/viniciusdaniel/53a98cbb1d8cac1bb473da23f5708836#foreground-text
    # https://www.postgresql.org/docs/current/app-psql.html#APP-PSQL-PROMPTING

(base) saanvi@ryzen9:PostgreSQL-Learning$ nano ~/.psqlrc
    ------------------- For Linux - With Colors ----------------------------
    \set PROMPT1 '%[%033[96m%]%n@%[%033[95m%]%m %[%033[39m%][%`date +%H:%M:%S`] %[%033[92m%](%/) \n%[%033[1;33m%]%R%#%]%[%033[0;39m%]%] '
    \set PROMPT2 '%[%033[1;33m%]%R%#%]%[%033[0;39m%]%] '
    ------------------- For Linux ----------------------------

    ------------------- For MAC - No colors----------------------------
    \set PROMPT1 '%n@%m [%`date +%H:%M:%S`] (%/) \n%R%#% '
    \set PROMPT2 '%R%#% '
    ------------------- For Linux ----------------------------