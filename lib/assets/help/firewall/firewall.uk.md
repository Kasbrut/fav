# Firewall і відкриття портів

## Що таке firewall

Firewall — це вартовий, який вирішує, якому мережевому трафіку дозволено досягати вашого сервера. Майже кожен хмарний провайдер запускає його перед вашою віртуальною машиною, і за замовчуванням він блокує весь вхідний трафік.

WireGuard за замовчуванням слухає на **UDP-порту 51820**. Щоб ваші пристрої могли досягти сервера, цей порт має бути явно дозволений у firewall.

## Що вам потрібно зробити

У панелі керування вашого провайдера знайдіть налаштування firewall (їх також називають *security group*, *cloud firewall* або *networking rules*) і додайте правило, яке дозволяє:

- **Протокол**: UDP
- **Порт**: 51820 (або той, який ви обрали)
- **Джерело**: будь-яке (`0.0.0.0/0` — ваші телефони можуть підключатися з багатьох мереж)
- **Напрямок**: вхідний

Збережіть і застосуйте. Правило зазвичай набуває чинності за кілька секунд.

## Документація провайдерів

У кожного провайдера власна панель керування. Нижче наведено посилання на офіційну документацію, яку самі провайдери підтримують в актуальному стані.

| Провайдер | Документація |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (пошук "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (пошук "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Зверніть увагу**: деякі провайдери (зокрема **IONOS**) за замовчуванням блокують весь вхідний трафік. Якщо встановлення завершилося успішно, але ви все одно не можете підключитися до VPN, це перше, що варто перевірити.

## Я використовую іншого провайдера

FAV налаштовує правила переадресації та NAT, потрібні для VPN, але не змінює UFW чи інший firewall сервера, щоб відкрити порт WireGuard. Якщо на сервері ввімкнено firewall, дозвольте в ньому вибраний UDP-порт, не замінюючи сторонні правила. Окремий firewall у панелі провайдера все одно потрібно налаштувати.
