# Firewall e abertura de portas

## O que é um firewall

Um firewall é um porteiro que decide qual tráfego de rede tem permissão para chegar ao seu servidor. Quase todo provedor de nuvem opera um na frente da sua máquina virtual, e ele bloqueia todo o tráfego de entrada por padrão.

O WireGuard escuta na **porta UDP 51820** por padrão. Para que os seus dispositivos alcancem o servidor, essa porta precisa ser explicitamente liberada no firewall.

## O que você precisa fazer

No painel do seu provedor, encontre as configurações de firewall (também chamadas de *security group*, *cloud firewall* ou *regras de rede*) e adicione uma regra que permita:

- **Protocolo**: UDP
- **Porta**: 51820 (ou a que você escolheu)
- **Origem**: qualquer lugar (`0.0.0.0/0` — seus celulares podem se conectar a partir de muitas redes)
- **Direção**: entrada

Salve e aplique. A regra normalmente entra em vigor em poucos segundos.

## Documentação dos provedores

Cada provedor tem o seu próprio painel. Abaixo estão links para a documentação oficial mantida atualizada pelos próprios provedores.

| Provedor | Documentação |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com (busque "VPS firewall") |
| Aruba Cloud | https://kb.arubacloud.com (busque "firewall") |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **Atenção**: alguns provedores (notadamente o **IONOS**) bloqueiam todo o tráfego de entrada por padrão. Se a sua instalação foi concluída com sucesso mas você ainda não consegue se conectar à VPN, essa é a primeira coisa a verificar.

## Estou em um provedor diferente

O FAV configura as regras de encaminhamento e NAT necessárias para a VPN, mas não altera o UFW nem outro firewall do servidor para expor a porta do WireGuard. Se houver um firewall ativo no servidor, permita nele a porta UDP escolhida sem substituir regras não relacionadas. Você ainda precisa configurar qualquer firewall separado no painel do provedor.
