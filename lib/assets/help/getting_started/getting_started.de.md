# Dein erster Server

Eine Schritt-für-Schritt-Anleitung — keine Vorkenntnisse erforderlich.

## 1. Eine virtuelle Maschine besorgen

Eine virtuelle Maschine (oft VPS genannt) ist ein kleiner Computer, der in einem Rechenzentrum läuft und durchgehend eingeschaltet ist. Du mietest ihn monatlich bei einem Cloud-Anbieter wie Linode, DigitalOcean, Hetzner oder Vultr. Der günstigste Tarif (typischerweise 1 geteilter CPU-Kern und 1 GB RAM) reicht für ein persönliches [VPN](glossary://vpn) mehr als aus.

Wähle beim Bestellen des Servers die neueste stabile Version von Debian oder Ubuntu als Betriebssystem. Notiere dir drei Dinge, bevor du das Dashboard des Anbieters schließt: die öffentliche IP-Adresse des Servers, den Login-Benutzernamen (meist `root`) und das Passwort, das dir der Anbieter gibt.

## 2. Den WireGuard-Port öffnen

Eine [Firewall](glossary://firewall) ist ein Filter, der entscheidet, welche Netzwerkverbindungen in deinen Server hinein- und aus ihm herausdürfen. Die meisten Cloud-Anbieter setzen standardmäßig eine Firewall ein, und sie blockiert alle Ports, die du nicht ausdrücklich geöffnet hast. WireGuard kommuniziert über einen [UDP-Port](glossary://udp-port) — standardmäßig 51820 —, daher musst du eine eingehende Regel hinzufügen, die UDP-Verkehr auf diesem Port erlaubt.

Schritt-für-Schritt-Anleitungen speziell für jeden großen Anbieter findest du im Eintrag „Firewall und Portfreigabe“ in diesem Hilfebereich. Das Bedienfeld jedes Anbieters sieht etwas anders aus, aber die Schritte sind dieselben: die Firewall-Regeln finden, eine eingehende UDP-Regel für Port 51820 hinzufügen und speichern.

## 3. Den Server zu dieser App hinzufügen

Öffne Server und wähle Server hinzufügen. Trage die öffentliche IP-Adresse, den SSH-Port (standardmäßig 22), den Benutzernamen und das Passwort aus Schritt 1 ein. Prüfe die erweiterten Optionen nur, wenn du WireGuard-Port, Subnetz, DNS, Härtung, Überwachung oder Sicherung ändern musst; wähle dann Verbinden und installieren.

Die App verbindet sich mit deinem Server über [SSH](glossary://ssh) — einen verschlüsselten Kanal — und zeigt dir sofort den [Fingerprint](glossary://fingerprint) des Servers an. Der Fingerprint ist ein kurzer Code, der den Server eindeutig identifiziert. Lies ihn und bestätige nur dann, wenn er mit dem übereinstimmt, was du im Dashboard deines Anbieters oder in der Konsolenausgabe siehst. Nach der Bestätigung merkt sich die App den Fingerprint und warnt dich, falls er sich jemals ändert — eine unerwartete Änderung kann ein Anzeichen für ein Sicherheitsproblem sein.

## 4. Auf die Installation warten

Nachdem du den Fingerprint bestätigt hast, prüft FAV den Server und startet die Installation. Sie läuft auf dem Server weiter, wenn du die App schließt. Öffne FAV erneut, um den Fortschritt abzurufen; sudo kann das Passwort erneut benötigen.

## 5. Deinen ersten Peer hinzufügen

Die Installation erstellt ein erstes Clientprofil. Weitere Profile erstellst du über Peer hinzufügen in den Serverdetails. Speichere oder teile auf demselben Gerät die .conf-Datei und öffne sie mit WireGuard. Öffne für ein anderes Gerät dort WireGuard, wähle den QR-Import und scanne den von FAV angezeigten Code.

Prüfe den importierten Tunnel, speichere und aktiviere ihn. Die genauen Bezeichnungen unterscheiden sich je nach WireGuard-Plattform und -Version; in den Peer-Details findest du plattformspezifische Anleitungen.

Dein Datenverkehr verwendet nun die IPv4- und IPv6-Standardrouten des Profils über deinen eigenen Server.

## IPv6 und sichere Profile

FAV wählt IPv6 automatisch. Mit einem vom Provider delegierten `/64` und verifiziertem Rückweg nutzt es geroutetes IPv6. Andernfalls nutzt es eine dauerhafte ULA: Das Profil erfasst IPv6 weiterhin, aber der Server weist es zurück, statt einen direkten Fallback zuzulassen. Es gibt keine IPv6-Bypass-Option.

Damit werden die Serverkonfiguration und das von FAV erzeugte Profil geprüft, nicht das Gerät, das es importiert. Export, gemeldeter Import oder Handshake beweisen weder Client-Routen noch Kill Switch oder Schutz bei gestoppter VPN. Unter Android aktiviere Always-on VPN und Verbindungen ohne VPN blockieren von WireGuard nur, falls vorhanden, und prüfe sie auf diesem Gerät. Für andere Plattformen Client-/OS-Schutz getrennt einrichten und testen. QR-Codes und .conf-Dateien enthalten private Schlüssel: teile sie nur mit dem vorgesehenen Gerät.
