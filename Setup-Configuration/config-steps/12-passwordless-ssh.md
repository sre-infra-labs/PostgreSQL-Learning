## 12. Passwordless SSH between hosts (for remote log / backup access)

```bash
sudo -u postgres ssh-keygen -t ed25519 -N ''
sudo -u postgres ssh-copy-id postgres@<remote-host>     # or copy ~postgres/.ssh/id_ed25519.pub manually
sudo -u postgres ssh postgres@<remote-host> 'echo ok'
```
