# Votre premier serveur

Un guide pas à pas — aucune expérience préalable requise.

## 1. Obtenir une machine virtuelle

Une machine virtuelle (souvent appelée VPS) est un petit ordinateur qui tourne dans un centre de données et reste toujours allumé. Vous le louez au mois auprès d'un fournisseur cloud tel que Linode, DigitalOcean, Hetzner ou Vultr. L'offre la moins chère (généralement 1 cœur CPU partagé et 1 Go de RAM) suffit largement à faire tourner un [VPN](glossary://vpn) personnel.

Lorsque vous commandez le serveur, choisissez la dernière version stable de Debian ou Ubuntu comme système d'exploitation. Notez trois choses avant de fermer le tableau de bord du fournisseur : l'adresse IP publique du serveur, le nom d'utilisateur de connexion (généralement `root`) et le mot de passe que le fournisseur vous fournit.

## 2. Ouvrir le port WireGuard

Un [firewall](glossary://firewall) est un filtre qui décide quelles connexions réseau sont autorisées en entrée et en sortie de votre serveur. La plupart des fournisseurs cloud appliquent un firewall par défaut, et il bloque tous les ports que vous n'avez pas explicitement ouverts. WireGuard communique sur un [port UDP](glossary://udp-port) — le port par défaut est 51820 — vous devez donc ajouter une règle entrante qui autorise le trafic UDP sur ce port.

Pour des instructions pas à pas propres à chaque grand fournisseur, consultez l'entrée « Firewall et ouverture de port » de cette section Aide. Le panneau de contrôle de chaque fournisseur a une apparence un peu différente, mais les étapes sont les mêmes : trouver les règles du firewall, ajouter une règle UDP entrante pour le port 51820, et enregistrer.

## 3. Ajouter le serveur à cette application

Ouvrez Serveurs et choisissez Ajouter un serveur. Saisissez l'adresse IP publique, le port SSH (22 par défaut), le nom d'utilisateur et le mot de passe de l'étape 1. Consultez les options avancées uniquement pour modifier le port WireGuard, le sous-réseau, le DNS, le renforcement, la surveillance ou la sauvegarde, puis choisissez Se connecter et installer.

L'application se connecte à votre serveur via [SSH](glossary://ssh) — un canal chiffré — et vous montre immédiatement l'[empreinte](glossary://fingerprint) du serveur. L'empreinte est un code court qui identifie le serveur de manière unique. Lisez-la et confirmez uniquement si elle correspond à ce que vous voyez dans le tableau de bord de votre fournisseur ou dans la sortie de la console. Une fois confirmée, l'application la mémorise et vous alertera si elle change un jour — un changement que vous n'attendiez pas peut être le signe d'un problème de sécurité.

## 4. Attendre l'installation

Après confirmation de l'empreinte, FAV vérifie le serveur et lance l'installation. Elle continue sur le serveur si vous fermez l'application. Rouvrez FAV pour récupérer la progression ; sudo peut redemander le mot de passe.

## 5. Ajouter votre premier peer

L'installation crée un premier profil client. Pour en créer un autre, utilisez Ajouter un pair dans les détails du serveur. Sur le même appareil, enregistrez ou partagez le fichier .conf et ouvrez-le avec WireGuard. Pour un autre appareil, ouvrez-y WireGuard, choisissez l'import par QR et scannez le code affiché par FAV.

Vérifiez le tunnel importé, enregistrez-le et activez-le. Les libellés exacts varient selon la plateforme et la version de WireGuard ; les détails du pair contiennent des instructions propres à chaque plateforme.

Votre trafic utilise désormais les routes par défaut IPv4 et IPv6 du profil via votre propre serveur.

## IPv6 et sécurité des profils

FAV choisit IPv6 automatiquement. Avec un `/64` délégué par le fournisseur et un chemin de retour vérifié, il utilise IPv6 routé. Sinon, il utilise une ULA persistante : le profil capture toujours IPv6, mais le serveur le rejette au lieu d'autoriser un repli direct. Il n'existe pas d'option de contournement IPv6.

Cela vérifie la configuration du serveur et le profil généré par FAV, pas l'appareil qui l'importe. L'export, une importation déclarée ou une poignée de main ne prouvent ni les routes du client, ni un kill switch, ni la protection lorsque le VPN est arrêté. Sur Android, activez VPN toujours actif et Bloquer les connexions sans VPN de WireGuard uniquement s'ils sont disponibles, puis vérifiez-les sur cet appareil. Sur les autres plateformes, configurez et testez séparément la protection client/OS. Les codes QR et fichiers .conf contiennent des clés privées : partagez-les uniquement avec l’appareil prévu.
