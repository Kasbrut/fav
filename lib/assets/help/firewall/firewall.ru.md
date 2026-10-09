# Firewall и открытие порта

## Что такое firewall

Firewall — это привратник, который решает, какому сетевому трафику разрешено достигать вашего сервера. Почти каждый облачный провайдер запускает его перед вашей виртуальной машиной, и по умолчанию он блокирует весь входящий трафик.

WireGuard по умолчанию слушает **UDP-порт 51820**. Чтобы ваши устройства могли достучаться до сервера, этот порт должен быть явно разрешён в firewall.

## Что нужно сделать

В панели управления вашего провайдера найдите настройки firewall (их также называют *security group*, *cloud firewall* или *networking rules*) и добавьте правило, которое разрешает:

- **Протокол**: UDP
- **Порт**: 51820 (или тот, который вы выбрали)
- **Источник**: откуда угодно (`0.0.0.0/0` — ваши телефоны могут подключаться из многих сетей)
- **Направление**: входящее

Сохраните и примените. Правило обычно вступает в силу за несколько секунд.

## Документация провайдеров

У каждого провайдера своя панель управления. Ниже приведены ссылки на официальную документацию, которую сами провайдеры поддерживают в актуальном состоянии.

| Провайдер | Документация |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (поиск "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (поиск "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Обратите внимание**: некоторые провайдеры (особенно **IONOS**) по умолчанию блокируют весь входящий трафик. Если установка прошла успешно, но вы по-прежнему не можете подключиться к VPN, это первое, что стоит проверить.

## Я использую другого провайдера

FAV настраивает правила переадресации и NAT, необходимые для VPN, но не изменяет UFW или другой firewall сервера, чтобы открыть порт WireGuard. Если на сервере включён firewall, разрешите в нём выбранный UDP-порт, не заменяя посторонние правила. Отдельный firewall в панели провайдера всё равно нужно настроить.
