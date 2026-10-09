# FAQ

## Cos'è una VPN, in una frase?

Una VPN è un tunnel tra il tuo dispositivo e un server: il traffico del tuo dispositivo sembra provenire dal server, e la connessione tra il tuo dispositivo e il server è cifrata.

## Perché ho bisogno di un mio server?

Controlli il server VPN e la sua configurazione. Devi comunque fidarti del provider di hosting e degli amministratori del server, che possono osservare i metadati di rete. Una VPN autogestita non ti rende anonimo.

## Quanto costa mantenerlo?

FAV è gratuito. I costi di hosting e traffico dipendono dal provider e dal piano: verifica prezzi e limiti aggiornati.

## La password che digito nell'app viene salvata sul dispositivo?

Le password di accesso e sudo vengono richieste quando servono e non vengono salvate nei dati dell’app. La chiave SSH viene generata durante l’installazione anche senza hardening e conservata nell’archivio sicuro.

## Posso trasferire il mio server su un altro dispositivo?

Sì. Apri Impostazioni → Backup e ripristino per creare un file `.favbackup` cifrato con password. Ripristinalo soltanto in un'installazione FAV vuota ed evita di gestire gli stessi server da entrambi i dispositivi: i dati locali potrebbero divergere. Se il vecchio dispositivo è stato perso o compromesso, il ripristino può ruotare le chiavi SSH di FAV e, dopo due conferme, revocare tutti i peer presenti sui server raggiungibili.

## L'app può far passare il mio dispositivo attraverso la VPN automaticamente?

Non ancora. Oggi l'app configura il server — il dispositivo si connette tramite l'app ufficiale WireGuard. Integrare il client in questa app è nella roadmap a lungo termine.

## Cosa fa "Abilita hardening"?

L'hardening (nelle Opzioni avanzate, disattivato di default) mette in sicurezza l'intero server dopo l'installazione: disabilita l'accesso SSH con password (resta solo il login a chiave), disabilita il login SSH come root e aggiunge la protezione anti brute-force. Si applica all'utente con cui l'app gestisce il server: quello che crea per un login come root, o il tuo utente esistente per un login non-root con sudo. L'app verifica prima che il login a chiave funzioni e annulla tutto automaticamente se qualcosa non va, ma tieni comunque a portata di mano la console del tuo provider come via di rientro.

## Come rimuovo un server?

In Server, scorri un server, usa il suo menu o scegli Rimuovi server nei dettagli. Seleziona **Rimuovi VPN e servizi** per eseguire il teardown remoto prima che FAV lo dimentichi; quando applicabile puoi anche annullare l'hardening SSH. Lascia l'opzione disattivata e scegli **Disconnetti FAV e rimuovi** per eliminare da remoto solo la chiave SSH di FAV, lasciando la VPN attiva. **Dimentica senza contattare il server** elimina solo i dati locali e lascia ogni modifica remota, inclusa la chiave SSH di FAV: usalo solo se il server non è raggiungibile o lo ripulirai tu. Puoi riprovare i passaggi remoti falliti prima della rimozione solo locale.

## Ho un problema — cosa faccio?

Controlla la sezione **Codici di errore** in questa scheda Aiuto se hai visto un errore rosso. Se non trovi una soluzione, usa **Segnala un problema** per aprire una issue precompilata su GitHub.

## IPv6 e sicurezza dei profili

I nuovi profili v2 includono le route predefinite IPv4 e IPv6; FAV non ha un'impostazione di bypass IPv6. Usa IPv6 instradato solo dopo aver verificato il percorso di ritorno di un `/64` delegato dal provider. Altrimenti la modalità bloccata cattura IPv6 in un tunnel ULA e lo rifiuta sul server, invece di usare IPv6 diretto. Un endpoint IPv6 pubblico non è questa prova.

FAV verifica solo il risultato del server e il profilo generato. Esportazione, importazione dichiarata e handshake WireGuard non verificano route o kill switch del client e non proteggono il traffico dopo l'arresto della VPN. Configura e verifica separatamente la protezione del client/OS. Su Android controlla sul dispositivo di destinazione VPN sempre attiva e Blocca connessioni senza VPN; FAV non ne ha verificato disponibilità e comportamento. Usa un server dedicato e mantieni l'accesso alla console. QR e file .conf contengono chiavi private: condividili solo con il dispositivo previsto.
