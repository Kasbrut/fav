# Firewall e apertura porte

## Che cos'è un firewall

Un firewall è un controllore che decide quale traffico di rete può raggiungere il tuo server. Quasi tutti i provider cloud ne hanno uno davanti alla tua macchina virtuale, e di default blocca tutto il traffico in ingresso.

WireGuard ascolta sulla **porta UDP 51820** per impostazione predefinita. Perché i tuoi dispositivi riescano a raggiungere il server, questa porta deve essere esplicitamente consentita nel firewall.

## Cosa devi fare

Nel pannello di controllo del tuo provider, cerca le impostazioni del firewall (chiamate anche *security group*, *cloud firewall* o *regole di rete*) e aggiungi una regola che consenta:

- **Protocollo**: UDP
- **Porta**: 51820 (o quella che hai scelto)
- **Sorgente**: ovunque (`0.0.0.0/0` — i tuoi telefoni si connettono da reti diverse)
- **Direzione**: in ingresso

Salva e applica. La regola di solito entra in vigore in pochi secondi.

## Documentazione dei provider

Ogni provider ha il proprio pannello. Di seguito trovi i link alla documentazione ufficiale, aggiornata dai provider stessi.

| Provider | Documentazione |
|----------|----------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (cerca "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (cerca "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Attenzione**: alcuni provider (in particolare **IONOS**) bloccano tutto il traffico in ingresso per impostazione predefinita. Se l'installazione è andata a buon fine ma non riesci ancora a connetterti alla VPN, questo è il primo punto da verificare.

## Sono su un altro provider

FAV configura le regole di forwarding e NAT necessarie alla VPN, ma non modifica UFW o un altro firewall del server per esporre la porta WireGuard. Se sul server è attivo un firewall, consenti lì la porta UDP scelta senza sostituire regole non correlate. Devi comunque configurare ogni firewall separato nel pannello del provider.
