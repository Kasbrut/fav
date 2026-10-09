# FAQ

## Was ist ein VPN, in einem Satz?

Ein VPN ist ein Tunnel zwischen deinem Gerät und einem Server: Der Datenverkehr deines Geräts scheint vom Server zu kommen, und die Verbindung zwischen deinem Gerät und dem Server ist verschlüsselt.

## Warum brauche ich meinen eigenen Server?

Du kontrollierst den VPN-Server und seine Konfiguration. Du musst weiterhin dem Hosting-Anbieter und den Serveradministratoren vertrauen, die Netzwerkmetadaten beobachten können. Ein selbst betriebenes VPN macht dich nicht anonym.

## Wie viel kostet der Betrieb?

FAV ist kostenlos. Hosting- und Datenverkehrskosten hängen von Anbieter und Tarif ab; prüfe die aktuellen Preise und Limits.

## Wird das Passwort, das ich in die App eingebe, auf meinem Gerät gespeichert?

Anmelde- und sudo-Passwörter werden bei Bedarf abgefragt und nicht als App-Daten gespeichert. Der SSH-Schlüssel wird bei der Einrichtung auch ohne Hardening erzeugt und im sicheren Speicher aufbewahrt.

## Kann ich meinen Server auf ein anderes Gerät übertragen?

Ja. Unter Einstellungen → Sicherung und Wiederherstellung kannst du eine passwortverschlüsselte `.favbackup`-Datei erstellen. Stelle sie nur in einer leeren FAV-Installation wieder her und verwalte dieselben Server nicht gleichzeitig von beiden Geräten. Bei Verlust oder Kompromittierung des alten Geräts kann FAV seine SSH-Schlüssel rotieren und nach zwei Bestätigungen alle vorhandenen Peers auf erreichbaren Servern widerrufen.

## Kann die App den Datenverkehr meines Geräts automatisch durch das VPN leiten?

Noch nicht. Heute richtet die App den Server ein — dein Gerät verbindet sich über die offizielle WireGuard-App. Den Client in diese App zu integrieren steht auf der langfristigen Roadmap.

## Was bewirkt „Härtung aktivieren"?

Die Härtung (in den erweiterten Optionen, standardmäßig aus) sichert nach der Installation den gesamten Server ab: Sie schaltet die SSH-Anmeldung per Passwort ab (nur noch Schlüssel-Login), deaktiviert die Root-SSH-Anmeldung und ergänzt einen Brute-Force-Schutz. Sie gilt für den Benutzer, als den die App den Server verwaltet — den Benutzer, den sie bei einer Root-Anmeldung anlegt, oder deinen vorhandenen Benutzer bei einer Nicht-Root-Sudo-Anmeldung. Die App prüft zuerst, dass deine schlüsselbasierte Anmeldung funktioniert, und macht alles automatisch rückgängig, falls etwas nicht stimmt — halte aber dennoch die Konsole deines Anbieters als Rückweg bereit.

## Wie entferne ich einen Server?

Wische unter Server über einen Server, nutze sein Menü oder wähle in den Details Server entfernen. Wähle **VPN und Dienste entfernen**, um vor dem Vergessen eine Remote-Bereinigung auszuführen; sofern zutreffend, kannst du auch die SSH-Härtung rückgängig machen. Lasse die Option aus und wähle **FAV trennen und entfernen**, um nur den SSH-Schlüssel von FAV remote zu löschen und das VPN weiterlaufen zu lassen. **Ohne Serverkontakt vergessen** löscht nur lokale Daten und belässt alle Remote-Änderungen einschließlich des FAV-SSH-Schlüssels; nutze es nur bei unerreichbarem Server oder wenn du selbst aufräumst. Fehlgeschlagene Remote-Schritte kannst du vor dem rein lokalen Entfernen wiederholen.

## Ich habe Probleme — was soll ich tun?

Sieh im Abschnitt **Fehlercodes** in diesem Hilfe-Tab nach, wenn du einen roten Fehler gesehen hast. Wenn du dann immer noch keine Lösung findest, nutze **Problem melden**, um ein vorausgefülltes GitHub-Issue zu öffnen.

## IPv6 und sichere Profile

Neue v2-Profile enthalten IPv4- und IPv6-Standardrouten; FAV hat keine IPv6-Bypass-Einstellung. Geroutetes IPv6 wird nur nach Prüfung des Rückwegs eines vom Provider delegierten `/64` verwendet. Sonst erfasst der blockierte Modus IPv6 in einem ULA-Tunnel und weist es auf dem Server zurück, statt direktes IPv6 zu verwenden. Ein öffentlicher IPv6-Endpunkt ist kein solcher Nachweis.

FAV prüft nur das Serverergebnis und das erzeugte Profil. Export, gemeldeter Import und ein WireGuard-Handshake prüfen weder die Routen des Ziel-Clients noch einen Kill Switch und schützen nicht nach VPN-Stopp. Client-/OS-Schutz getrennt konfigurieren und validieren. Prüfe auf Android am Zielgerät Always-on VPN und Verbindungen ohne VPN blockieren; Verfügbarkeit und Verhalten sind nicht von FAV geprüft. Verwende einen dedizierten Server und behalte Konsolenzugriff. QR-Codes und .conf-Dateien enthalten private Schlüssel: teile sie nur mit dem vorgesehenen Gerät.
