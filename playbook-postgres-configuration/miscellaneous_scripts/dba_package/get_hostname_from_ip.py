import socket

def get_hostname_from_ip(ip_address):
    try:
        hostname = socket.gethostbyaddr(ip_address)
        return hostname[0]  # returns the primary hostname
    except socket.herror:
        return None  # Could not resolve
