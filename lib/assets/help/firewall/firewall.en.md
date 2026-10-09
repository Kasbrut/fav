# Firewall and port opening

## What a firewall is

A firewall is a gatekeeper that decides which network traffic is allowed to reach your server. Almost every cloud provider runs one in front of your virtual machine, and it blocks all incoming traffic by default.

WireGuard listens on **UDP port 51820** by default. For your devices to reach the server, this port has to be explicitly allowed in the firewall.

## What you need to do

In your provider's dashboard, find the firewall settings (also called *security group*, *cloud firewall*, or *networking rules*) and add a rule that allows:

- **Protocol**: UDP
- **Port**: 51820 (or whichever you chose)
- **Source**: anywhere (`0.0.0.0/0` — your phones can connect from many networks)
- **Direction**: incoming

Save and apply. The rule usually takes effect in a few seconds.

## Provider documentation

Each provider has its own dashboard. Below are links to the official documentation kept up to date by the providers themselves.

| Provider | Documentation |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (search "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (search "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Heads-up**: some providers (notably **IONOS**) block all incoming traffic by default. If your installation succeeded but you still cannot connect to the VPN, this is the first thing to check.

## I am on a different provider

FAV configures the forwarding and NAT rules needed by the VPN, but it does not change UFW or another host firewall to expose the WireGuard port. If your server has a host firewall enabled, allow the selected UDP port there without replacing unrelated rules. You must still configure any separate firewall in the provider dashboard.
