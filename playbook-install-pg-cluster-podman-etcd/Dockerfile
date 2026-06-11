FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker

# Install systemd, SSH, and base utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        dbus \
        openssh-server \
        sudo \
        python3 \
        python3-pip \
        curl \
        wget \
        gnupg2 \
        ca-certificates \
        less \
        inetutils-ping \
        jq \
        acl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Remove unnecessary systemd units that break container startup
RUN find /etc/systemd/system /lib/systemd/system \
        -path '*.wants/*' \
        \( -name '*getty*' \
        -o -name '*apt-daily*' \
        -o -name '*systemd-timesyncd*' \
        -o -name '*systemd-logind*' \
        -o -name '*systemd-vconsole-setup*' \
        -o -name '*systemd-readahead*' \
        -o -name '*udev*' \
        -o -name '*fstrim*' \
        -o -name '*e2scrub*' \
        -o -name '*dpkg*' \
        -o -name '*motd*' \) \
        -exec rm -f {} \; 2>/dev/null || true

# Mask problematic services that cause systemd to fail in containers
RUN systemctl mask systemd-pstore.service 2>/dev/null || true \
    && systemctl mask systemd-logind.service 2>/dev/null || true \
    && systemctl mask e2scrub_reap.service 2>/dev/null || true

# Configure SSH daemon
RUN ssh-keygen -A \
    && mkdir -p /var/run/sshd \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config \
    && echo "AllowUsers ansible" >> /etc/ssh/sshd_config

# Create ansible user with passwordless sudo
RUN useradd -m -s /bin/bash ansible \
    && echo "ansible ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ansible \
    && chmod 440 /etc/sudoers.d/ansible \
    && mkdir -p /home/ansible/.ssh \
    && chmod 700 /home/ansible/.ssh \
    && chown -R ansible:ansible /home/ansible/.ssh

# Enable SSH service
RUN systemctl enable ssh

EXPOSE 22

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
