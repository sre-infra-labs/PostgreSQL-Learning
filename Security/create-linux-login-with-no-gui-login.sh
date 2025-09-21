# create user
sudo adduser ajay --shell /bin/bash

# grant sudo access
sudo usermod -aG sudo ajay

# check the login details in /etc/passwd should look like below
ajay:x:1002:1002:Ajay Kumar Dwivedi,,,:/home/ajay:/bin/bash

# Disable GUI login manager
sudo touch /home/ajay/.noxsession
sudo chown ajay:ajay /home/ajay/.noxsession

# Restrict GUI login in lightdm
    # https://askubuntu.com/a/575390
sudo nano /var/lib/AccountsService/users/ajay

    [User]
    Session=
    Icon=/home/ajay/.face
    SystemAccount=true

sudo systemctl restart accounts-daemon.service


# Configure LightDM to Enable NumLock
sudo apt update
sudo apt install numlockx
sudo nano /etc/lightdm/lightdm.conf.d/50-numlock.conf

[Seat:*]
greeter-setup-script=/usr/bin/numlockx on


