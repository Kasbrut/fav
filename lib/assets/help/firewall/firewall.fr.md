# Firewall et ouverture de port

## Ce qu'est un firewall

Un firewall est un gardien qui décide quel trafic réseau est autorisé à atteindre votre serveur. Presque tous les fournisseurs cloud en font tourner un devant votre machine virtuelle, et il bloque par défaut tout le trafic entrant.

WireGuard écoute par défaut sur le **port UDP 51820**. Pour que vos appareils puissent atteindre le serveur, ce port doit être explicitement autorisé dans le firewall.

## Ce que vous devez faire

Dans le tableau de bord de votre fournisseur, trouvez les réglages du firewall (aussi appelés *security group*, *cloud firewall* ou *networking rules*) et ajoutez une règle qui autorise :

- **Protocole** : UDP
- **Port** : 51820 (ou celui que vous avez choisi)
- **Source** : n'importe où (`0.0.0.0/0` — vos téléphones peuvent se connecter depuis de nombreux réseaux)
- **Direction** : entrant

Enregistrez et appliquez. La règle prend généralement effet en quelques secondes.

## Documentation des fournisseurs

Chaque fournisseur a son propre tableau de bord. Vous trouverez ci-dessous des liens vers la documentation officielle, tenue à jour par les fournisseurs eux-mêmes.

| Fournisseur | Documentation |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (rechercher « VPS firewall ») |
| Aruba Cloud | https://kb.arubacloud.com (rechercher « firewall ») |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **À noter** : certains fournisseurs (notamment **IONOS**) bloquent par défaut tout le trafic entrant. Si votre installation a réussi mais que vous ne parvenez toujours pas à vous connecter au VPN, c'est la première chose à vérifier.

## Je suis chez un autre fournisseur

FAV configure les règles de transfert et de NAT nécessaires au VPN, mais ne modifie pas UFW ni un autre pare-feu de l'hôte pour exposer le port WireGuard. Si un pare-feu est actif sur le serveur, autorisez-y le port UDP choisi sans remplacer les règles sans rapport. Vous devez toujours configurer séparément le pare-feu du tableau de bord du fournisseur.
