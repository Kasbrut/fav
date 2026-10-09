# Firewall ve port açma

## Firewall nedir

Firewall, hangi ağ trafiğinin sunucunuza ulaşmasına izin verileceğine karar veren bir bekçidir. Neredeyse her bulut sağlayıcı sanal makinenizin önünde bir tane çalıştırır ve varsayılan olarak gelen tüm trafiği engeller.

WireGuard varsayılan olarak **UDP port 51820** üzerinden dinler. Cihazlarınızın sunucuya ulaşabilmesi için bu portun firewall'da açıkça izinli olması gerekir.

## Yapmanız gerekenler

Sağlayıcınızın kontrol panelinde firewall ayarlarını bulun (*security group*, *cloud firewall* veya *networking rules* olarak da adlandırılır) ve şunlara izin veren bir kural ekleyin:

- **Protokol**: UDP
- **Port**: 51820 (ya da hangisini seçtiyseniz)
- **Kaynak**: her yer (`0.0.0.0/0` — telefonlarınız birçok ağdan bağlanabilir)
- **Yön**: gelen

Kaydedip uygulayın. Kural genellikle birkaç saniye içinde etkin olur.

## Sağlayıcı belgeleri

Her sağlayıcının kendi kontrol paneli vardır. Aşağıda, sağlayıcıların kendileri tarafından güncel tutulan resmi belgelere bağlantılar bulunmaktadır.

| Sağlayıcı | Belgeler |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (search "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (search "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Dikkat**: bazı sağlayıcılar (özellikle **IONOS**) varsayılan olarak gelen tüm trafiği engeller. Kurulumunuz başarılı olduğu halde hâlâ VPN'e bağlanamıyorsanız, ilk kontrol etmeniz gereken şey budur.

## Farklı bir sağlayıcıdayım

FAV, VPN için gereken yönlendirme ve NAT kurallarını yapılandırır; ancak WireGuard portunu açmak için UFW'yi veya başka bir sunucu firewall'ını değiştirmez. Sunucuda bir firewall etkinse ilgisiz kuralları değiştirmeden seçilen UDP portuna izin verin. Sağlayıcı panelindeki ayrı firewall'ı yine de yapılandırmanız gerekir.
