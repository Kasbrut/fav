# Il tuo primo server

Una guida passo passo — nessuna esperienza precedente richiesta.

## 1. Procurati una macchina virtuale

Una macchina virtuale (spesso chiamata VPS) è un piccolo computer che gira in un data centre ed è sempre acceso. La si affitta mensilmente da un provider cloud come Linode, DigitalOcean, Hetzner o Vultr. Il piano più economico — di solito 1 CPU condivisa e 1 GB di RAM — è più che sufficiente per una [VPN](glossary://vpn) personale.

Al momento dell'ordine, scegli l'ultima versione stabile di Debian o Ubuntu come sistema operativo. Annota tre cose prima di chiudere il pannello del provider: l'indirizzo IP pubblico del server, il nome utente di accesso (di solito `root`) e la password fornita dal provider.

## 2. Apri la porta WireGuard

Un [firewall](glossary://firewall) è un filtro che decide quali connessioni di rete sono permesse in entrata e in uscita dal server. La maggior parte dei provider cloud applica un firewall di default che blocca tutte le porte non aperte esplicitamente. WireGuard comunica tramite una [porta UDP](glossary://udp-port) — di default la 51820 — quindi è necessario aggiungere una regola in entrata che consenta il traffico UDP su quella porta.

Per istruzioni specifiche ai principali provider, consulta la sezione "Firewall e apertura porte" in questa guida. Il pannello di controllo varia da provider a provider, ma i passi sono sempre gli stessi: trova le regole del firewall, aggiungi una regola UDP in entrata per la porta 51820 e salva.

## 3. Aggiungi il server all'app

Apri Server e scegli Aggiungi un server. Inserisci l'indirizzo IP pubblico, la porta SSH (22 di default), il nome utente e la password annotati al punto 1. Controlla le Opzioni avanzate solo se devi cambiare porta WireGuard, subnet, DNS, hardening, monitoraggio o backup; quindi scegli Connetti e installa.

L'app si connette al server tramite [SSH](glossary://ssh) — un canale cifrato — e mostra subito il [fingerprint](glossary://fingerprint) del server. Il fingerprint è un breve codice che identifica in modo univoco il server. Confermalo solo se corrisponde a quanto mostrato nel pannello del provider o nell'output della console. Una volta confermato, l'app lo memorizza e ti avvisa se dovesse cambiare — un cambiamento inatteso può essere segnale di un problema di sicurezza.

## 4. Attendi l'installazione

Dopo che confermi il fingerprint, FAV controlla il server e avvia l'installazione. Il processo continua sul server se chiudi l'app. Riapri FAV per recuperare lo stato; sudo potrebbe richiedere di nuovo la password.

## 5. Aggiungi il tuo primo peer

L'installazione crea un primo profilo client. Per crearne un altro, usa Aggiungi peer nei dettagli del server. Sullo stesso dispositivo, salva o condividi il file .conf e aprilo con WireGuard. Per importarlo su un altro dispositivo, apri WireGuard su quel dispositivo, scegli l'importazione tramite QR e scansiona il codice mostrato da FAV.

Controlla il tunnel importato, salvalo e attivalo. Le etichette esatte variano in base alla piattaforma e alla versione di WireGuard; nei dettagli del peer trovi istruzioni specifiche per piattaforma.

Il tuo traffico ora usa le route predefinite IPv4 e IPv6 del profilo attraverso il tuo server.

## IPv6 e sicurezza dei profili

FAV sceglie IPv6 automaticamente. Con un `/64` delegato dal provider e un percorso di ritorno verificato usa IPv6 instradato. Altrimenti usa una ULA persistente: il profilo cattura comunque IPv6, ma il server lo rifiuta invece di consentire un fallback diretto. Non esiste un'opzione di bypass IPv6.

Questo verifica la configurazione del server e il profilo generato da FAV, non il dispositivo che lo importa. Esportazione, importazione dichiarata o handshake non dimostrano route del client, kill switch o protezione quando la VPN è arrestata. Su Android abilita VPN sempre attiva e Blocca connessioni senza VPN di WireGuard solo se disponibili, quindi verificale su quel dispositivo. Per le altre piattaforme configura e prova separatamente la protezione del client/OS. QR e file .conf contengono chiavi private: condividili solo con il dispositivo previsto.
