# Firewall und Portfreigabe

## Was eine Firewall ist

Eine Firewall ist ein Türsteher, der entscheidet, welcher Netzwerkverkehr deinen Server erreichen darf. Nahezu jeder Cloud-Anbieter betreibt eine vor deiner virtuellen Maschine, und sie blockiert standardmäßig den gesamten eingehenden Verkehr.

WireGuard lauscht standardmäßig auf **UDP-Port 51820**. Damit deine Geräte den Server erreichen können, muss dieser Port in der Firewall ausdrücklich freigegeben werden.

## Was du tun musst

Suche im Dashboard deines Anbieters die Firewall-Einstellungen (auch *Security Group*, *Cloud Firewall* oder *Networking Rules* genannt) und füge eine Regel hinzu, die Folgendes erlaubt:

- **Protokoll**: UDP
- **Port**: 51820 (oder den von dir gewählten)
- **Quelle**: überall (`0.0.0.0/0` — deine Telefone können sich aus vielen Netzwerken verbinden)
- **Richtung**: eingehend

Speichern und anwenden. Die Regel wird üblicherweise innerhalb weniger Sekunden wirksam.

## Anbieter-Dokumentation

Jeder Anbieter hat sein eigenes Dashboard. Nachfolgend Links zur offiziellen Dokumentation, die von den Anbietern selbst aktuell gehalten wird.

| Anbieter | Dokumentation |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (suche nach "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (suche nach "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Achtung**: Manche Anbieter (insbesondere **IONOS**) blockieren standardmäßig den gesamten eingehenden Verkehr. Wenn deine Installation erfolgreich war, du dich aber trotzdem nicht mit dem VPN verbinden kannst, solltest du dies als Erstes prüfen.

## Ich nutze einen anderen Anbieter

FAV richtet die für das VPN nötigen Weiterleitungs- und NAT-Regeln ein, ändert aber weder UFW noch eine andere Host-Firewall, um den WireGuard-Port freizugeben. Ist auf dem Server eine Firewall aktiv, erlaube dort den gewählten UDP-Port, ohne andere Regeln zu ersetzen. Eine separate Firewall im Anbieter-Dashboard musst du weiterhin konfigurieren.
