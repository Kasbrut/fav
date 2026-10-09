# Perguntas frequentes

## O que é uma VPN, em uma frase?

Uma VPN é um túnel entre o seu dispositivo e um servidor: o tráfego do seu dispositivo parece vir do servidor, e a conexão entre o seu dispositivo e o servidor é criptografada.

## Por que eu preciso do meu próprio servidor?

Você controla o servidor VPN e sua configuração. Ainda precisa confiar no provedor de hospedagem e nos administradores, que podem observar metadados de rede. Uma VPN própria não torna você anônimo.

## Quanto custa para manter?

O FAV é gratuito. Os custos de hospedagem e tráfego dependem do provedor e do plano; consulte os preços e limites atuais.

## A senha que eu digito no app fica armazenada no meu dispositivo?

As senhas de acesso e sudo são solicitadas quando necessárias e não são salvas como dados do app. A chave SSH é gerada durante a instalação, mesmo sem hardening, e mantida no armazenamento seguro.

## Posso mover o meu servidor para outro dispositivo?

Sim. Abra Definições → Backup e restauro para criar um ficheiro `.favbackup` cifrado por palavra-passe. Restaure-o apenas numa instalação FAV vazia e evite gerir os mesmos servidores nos dois dispositivos. Se o dispositivo anterior foi perdido ou comprometido, o FAV pode rodar as suas chaves SSH e, após duas confirmações, revogar todos os peers existentes nos servidores acessíveis.

## O app pode rotear o meu dispositivo pela VPN automaticamente?

Ainda não. Hoje o app configura o servidor — o seu dispositivo se conecta pelo app oficial do WireGuard. Embutir o cliente neste app está no roadmap de longo prazo.

## O que faz "Ativar proteção"?

A proteção (nas Opções avançadas, desativada por padrão) blinda todo o servidor após a instalação: desativa o login SSH por senha (apenas login por chave), desativa o login SSH como root e adiciona proteção contra força bruta. Aplica-se ao usuário com que o app gerencia o servidor — o que ele cria para um login como root, ou o seu usuário existente para um login sudo não root. O app primeiro verifica que o seu login por chave funciona e reverte tudo automaticamente se algo der errado, mas mantenha sempre o console do seu provedor à mão como forma de voltar a entrar.

## Como removo um servidor?

Em Servidores, deslize um servidor, use o menu dele ou escolha Remover servidor nos detalhes. Selecione **Remover VPN e serviços** para fazer a limpeza remota antes que o FAV o esqueça; quando aplicável, você também pode desfazer a proteção SSH. Deixe a opção desmarcada e escolha **Desconectar o FAV e remover** para apagar remotamente apenas a chave SSH do FAV e manter a VPN ativa. **Esquecer sem contatar o servidor** remove somente os dados locais e mantém todas as alterações remotas, inclusive a chave SSH do FAV; use apenas se o servidor estiver inacessível ou se você mesmo for limpá-lo. Etapas remotas com falha podem ser tentadas novamente antes da remoção apenas local.

## Estou com dificuldades — o que devo fazer?

Verifique a seção **Códigos de erro** nesta aba de Ajuda se você viu um erro em vermelho. Se ainda assim não encontrar uma solução, use **Relatar um problema** para abrir uma issue pré-preenchida no GitHub.

## IPv6 e segurança dos perfis

Os novos perfis v2 incluem rotas padrão IPv4 e IPv6; o FAV não possui ajuste de desvio de IPv6. Só usa IPv6 roteado após verificar o caminho de retorno de um `/64` delegado pelo provedor. Caso contrário, o modo bloqueado captura IPv6 num túnel ULA e o rejeita no servidor, em vez de usar IPv6 direto. Um endpoint IPv6 público não é essa evidência.

O FAV verifica apenas o resultado do servidor e o perfil gerado. Exportação, importação declarada e handshake WireGuard não verificam as rotas nem um kill switch do cliente de destino e não protegem o tráfego após a VPN parar. Configure e valide separadamente a proteção do cliente/SO. No Android, verifique VPN sempre ativa e Bloquear conexões sem VPN no dispositivo de destino; o FAV não verificou disponibilidade nem comportamento. Use um servidor dedicado e mantenha acesso ao console. Códigos QR e arquivos .conf contêm chaves privadas: compartilhe-os apenas com o dispositivo pretendido.
