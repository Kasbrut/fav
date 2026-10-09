# Seu primeiro servidor

Um passo a passo completo — nenhuma experiência prévia necessária.

## 1. Obtenha uma máquina virtual

Uma máquina virtual (muitas vezes chamada de VPS) é um pequeno computador que roda em um data center e fica sempre ligado. Você o aluga por mês de um provedor de nuvem como Linode, DigitalOcean, Hetzner ou Vultr. O plano mais barato (normalmente 1 núcleo de CPU compartilhado e 1 GB de RAM) é mais do que suficiente para rodar uma [VPN](glossary://vpn) pessoal.

Ao contratar o servidor, escolha a versão estável mais recente do Debian ou do Ubuntu como sistema operacional. Anote três coisas antes de fechar o painel do provedor: o endereço IP público do servidor, o nome de usuário de login (geralmente `root`) e a senha que o provedor fornece.

## 2. Abra a porta do WireGuard

Um [firewall](glossary://firewall) é um filtro que decide quais conexões de rede têm permissão de entrada e de saída no seu servidor. A maioria dos provedores de nuvem aplica um firewall por padrão, e ele bloqueia todas as portas que você não abriu explicitamente. O WireGuard se comunica por uma [porta UDP](glossary://udp-port) — o padrão é 51820 — então você precisa adicionar uma regra de entrada que permita tráfego UDP nessa porta.

Para instruções passo a passo específicas de cada grande provedor, consulte o item "Firewall e abertura de portas" nesta seção de Ajuda. O painel de controle de cada provedor é um pouco diferente, mas os passos são os mesmos: encontre as regras de firewall, adicione uma regra de entrada UDP para a porta 51820 e salve.

## 3. Adicione o servidor a este app

Abra Servidores e escolha Adicionar servidor. Informe o endereço IP público, a porta SSH (22 por padrão), o nome de usuário e a senha do passo 1. Confira as Opções avançadas somente se precisar alterar a porta do WireGuard, a sub-rede, o DNS, a proteção, o monitoramento ou o backup; depois escolha Conectar e instalar.

O app se conecta ao seu servidor por [SSH](glossary://ssh) — um canal criptografado — e imediatamente mostra a você o [fingerprint](glossary://fingerprint) do servidor. O fingerprint é um código curto que identifica o servidor de forma única. Leia-o e confirme apenas se ele corresponder ao que você vê no painel do seu provedor ou na saída do console. Uma vez confirmado, o app o memoriza e vai alertá-lo se ele algum dia mudar — uma mudança que você não esperava pode ser sinal de um problema de segurança.

## 4. Aguarde a instalação

Depois de confirmar o fingerprint, o FAV verifica o servidor e inicia a instalação. Ela continua no servidor se você fechar o app. Abra o FAV novamente para recuperar o progresso; sudo pode solicitar a senha outra vez.

## 5. Adicione o seu primeiro peer

A instalação cria um primeiro perfil de cliente. Para criar outro, use Adicionar peer nos detalhes do servidor. No mesmo dispositivo, salve ou compartilhe o arquivo .conf e abra-o com o WireGuard. Para outro dispositivo, abra o WireGuard nele, escolha a importação por QR e leia o código exibido pelo FAV.

Confira o túnel importado, salve-o e ative-o. Os nomes exatos variam conforme a plataforma e a versão do WireGuard; os detalhes do peer incluem instruções específicas para cada plataforma.

O seu tráfego agora usa as rotas padrão IPv4 e IPv6 do perfil pelo seu próprio servidor.

## IPv6 e segurança dos perfis

O FAV escolhe IPv6 automaticamente. Com um `/64` delegado pelo provedor e caminho de retorno verificado, usa IPv6 roteado. Caso contrário, usa uma ULA persistente: o perfil ainda captura IPv6, mas o servidor o rejeita em vez de permitir um retorno direto. Não há opção de desvio de IPv6.

Isto verifica a configuração do servidor e o perfil gerado pelo FAV, não o dispositivo que o importa. Exportar, declarar uma importação ou ver um handshake não prova rotas do cliente, kill switch nem proteção quando a VPN para. No Android, ative VPN sempre ativa e Bloquear conexões sem VPN do WireGuard apenas se disponíveis e valide-as nesse dispositivo. Em outras plataformas, configure e teste separadamente a proteção do cliente/SO. Códigos QR e arquivos .conf contêm chaves privadas: compartilhe-os apenas com o dispositivo pretendido.
