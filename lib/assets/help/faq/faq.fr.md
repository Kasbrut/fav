# FAQ

## Qu'est-ce qu'un VPN, en une phrase ?

Un VPN est un tunnel entre votre appareil et un serveur : le trafic de votre appareil semble provenir du serveur, et la connexion entre votre appareil et le serveur est chiffrée.

## Pourquoi ai-je besoin de mon propre serveur ?

Vous contrôlez le serveur VPN et sa configuration. Vous devez toujours faire confiance à l’hébergeur et aux administrateurs, qui peuvent observer les métadonnées réseau. Un VPN autohébergé ne vous rend pas anonyme.

## Combien coûte son fonctionnement ?

FAV est gratuit. Les frais d’hébergement et de trafic dépendent du fournisseur et du forfait ; consultez leurs tarifs et limites actuels.

## Le mot de passe que je saisis dans l'application est-il stocké sur mon appareil ?

Les mots de passe de connexion et sudo sont demandés au besoin et ne sont pas enregistrés dans les données de l’application. La clé SSH est créée pendant l’installation, même sans durcissement, et conservée dans le stockage sécurisé.

## Puis-je déplacer mon serveur vers un autre appareil ?

Oui. Ouvrez Réglages → Sauvegarde et restauration pour créer un fichier `.favbackup` chiffré par mot de passe. Restaurez-le uniquement dans une installation FAV vide et évitez de gérer les mêmes serveurs depuis les deux appareils. Si l'ancien appareil est perdu ou compromis, FAV peut renouveler ses clés SSH et, après deux confirmations, révoquer tous les pairs présents sur les serveurs accessibles.

## L'application peut-elle faire passer mon appareil par le VPN automatiquement ?

Pas encore. Aujourd'hui, l'application configure le serveur — votre appareil se connecte via l'application officielle WireGuard. Intégrer le client à cette application figure sur la feuille de route à long terme.

## Que fait « Activer le renforcement » ?

Le renforcement (dans les options avancées, désactivé par défaut) verrouille tout le serveur après l'installation : il désactive la connexion SSH par mot de passe (connexion par clé uniquement), désactive la connexion SSH root et ajoute une protection contre la force brute. Il s'applique à l'utilisateur avec lequel l'application gère le serveur — celui qu'elle crée pour une connexion root, ou votre utilisateur existant pour une connexion sudo non root. L'application vérifie d'abord que votre connexion par clé fonctionne et annule tout automatiquement en cas de problème, mais gardez toujours la console de votre fournisseur à portée de main comme moyen de revenir.

## Comment supprimer un serveur ?

Dans Serveurs, balayez un serveur, utilisez son menu ou choisissez Supprimer le serveur dans ses détails. Sélectionnez **Supprimer le VPN et les services** pour effectuer le nettoyage distant avant que FAV ne l'oublie ; le cas échéant, vous pouvez aussi annuler le renforcement SSH. Laissez cette option désactivée et choisissez **Déconnecter FAV et supprimer** pour retirer à distance uniquement la clé SSH de FAV tout en laissant le VPN actif. **Oublier sans contacter le serveur** efface seulement les données locales et conserve toutes les modifications distantes, y compris la clé SSH de FAV ; utilisez-le uniquement si le serveur est inaccessible ou si vous le nettoierez vous-même. Vous pouvez réessayer les étapes distantes ayant échoué avant une suppression locale uniquement.

## J'ai un problème — que dois-je faire ?

Consultez la section **Codes d'erreur** de cet onglet Aide si vous avez vu une erreur rouge. Si vous ne trouvez toujours pas de solution, utilisez **Signaler un problème** pour ouvrir un ticket GitHub prérempli.

## IPv6 et sécurité des profils

Les nouveaux profils v2 comprennent les routes par défaut IPv4 et IPv6 ; FAV n'a pas de réglage de contournement IPv6. IPv6 routé n'est utilisé qu'après vérification du chemin de retour d'un `/64` délégué par le fournisseur. Sinon, le mode bloqué capture IPv6 dans un tunnel ULA et le rejette sur le serveur au lieu d'utiliser IPv6 directement. Un endpoint IPv6 public n'est pas cette preuve.

FAV vérifie seulement le résultat serveur et le profil généré. Export, importation déclarée et poignée de main WireGuard ne vérifient ni les routes du client de destination ni un kill switch, et ne protègent pas le trafic après l'arrêt du VPN. Configurez et validez séparément la protection client/OS. Sur Android, vérifiez VPN toujours actif et Bloquer les connexions sans VPN sur l'appareil cible ; FAV n'a pas vérifié leur disponibilité ni leur comportement. Utilisez un serveur dédié et conservez l’accès à la console. Les codes QR et fichiers .conf contiennent des clés privées : partagez-les uniquement avec l’appareil prévu.
