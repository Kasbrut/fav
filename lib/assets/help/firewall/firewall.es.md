# Firewall y apertura de puertos

## Qué es un firewall

Un firewall es un guardián que decide qué tráfico de red puede llegar a tu servidor. Casi todos los proveedores en la nube ejecutan uno delante de tu máquina virtual, y bloquea todo el tráfico entrante de forma predeterminada.

WireGuard escucha en el **puerto UDP 51820** de forma predeterminada. Para que tus dispositivos puedan alcanzar el servidor, este puerto debe permitirse explícitamente en el firewall.

## Qué tienes que hacer

En el panel de control de tu proveedor, busca la configuración del firewall (también llamada *security group*, *cloud firewall* o *reglas de red*) y añade una regla que permita:

- **Protocolo**: UDP
- **Puerto**: 51820 (o el que hayas elegido)
- **Origen**: cualquiera (`0.0.0.0/0` — tus teléfonos pueden conectarse desde muchas redes)
- **Dirección**: entrante

Guarda y aplica. La regla suele entrar en vigor en unos segundos.

## Documentación del proveedor

Cada proveedor tiene su propio panel de control. A continuación encontrarás enlaces a la documentación oficial que los propios proveedores mantienen actualizada.

| Proveedor | Documentación |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (busca "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (busca "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Atención**: algunos proveedores (en particular **IONOS**) bloquean todo el tráfico entrante de forma predeterminada. Si tu instalación se completó correctamente pero aun así no puedes conectarte a la VPN, esto es lo primero que debes comprobar.

## Estoy con un proveedor distinto

FAV configura las reglas de reenvío y NAT necesarias para la VPN, pero no modifica UFW ni otro cortafuegos del servidor para exponer el puerto de WireGuard. Si el servidor tiene un cortafuegos activo, permite allí el puerto UDP elegido sin sustituir reglas ajenas. También debes configurar cualquier cortafuegos separado del panel del proveedor.
