# SPEC-02: Protocollo di rete

## 1. Costanti

| Nome | Valore | Note |
|---|---|---|
| `PREFIX` | `AzGF` | prefisso dei messaggi degli addon (≤ 16 caratteri), registrato al caricamento |
| `CHANNEL` | `AzGuildFinder` | canale personalizzato **permanente** (i temporanei non accettano messaggi degli addon). **Il nome non deve più cambiare dopo il rilascio**: il gioco può conservare i canali abbandonati |
| `PROTO` | `1` | versione del protocollo, presente in ogni messaggio |
| `MAX_MSG` | 255 byte | limite del client; i messaggi più lunghi li divide AceComm |
| `CHANNEL_GAP` | 1,2 s | intervallo minimo tra due invii nel canale (dato pratico di OneForAll) |

Il canale viene nascosto da tutte le finestre della chat (`ChatFrame_RemoveChannel`), spostato in fondo all'elenco così `/1` resta il canale Generale, e i suoi avvisi di entrata e uscita vengono filtrati. Se l'entrata fallisce si riprova ogni 60 s (stesso schema di OneForAll e totalRP3).

Il modulo `Net/Channel` (M1.8) fa così:

- **Entrata**: 5 s dopo l'ingresso nel mondo (il client entra prima nei propri canali) chiama `JoinChannelByName("AzGuildFinder")` e aspetta la risposta per 5 s: un avviso `YOU_JOINED` per il nostro canale conferma l'entrata. Mai un canale temporaneo. Se il canale c'è già (dopo un `/reload`) lo adotta senza una seconda entrata; se il giocatore lo lascia con `/leave`, riprova dopo 60 s.
- **Nascondere e spostare**: toglie il canale da tutte le finestre subito, dopo 1 s e dopo 5 s (il client può riaggiungerlo dopo l'avviso) e a ogni schermata di caricamento; lo sposta in fondo con `C_ChatInfo.SwapChatChannelsByChannelIndex`, ma non durante il combattimento (finisce a `PLAYER_REGEN_ENABLED`). Il numero del canale cambia con lo spostamento: il `Transport` lo chiede ogni volta (`Transport.channelId`).
- **Filtri**: `CHAT_MSG_CHANNEL_NOTICE`, `CHAT_MSG_CHANNEL_NOTICE_USER`, `CHAT_MSG_CHANNEL_JOIN`, `CHAT_MSG_CHANNEL_LEAVE` e `CHAT_MSG_CHANNEL` con il nome `AzGuildFinder` sono nascosti con `ChatFrame_AddMessageEventFilter`; gli altri canali non cambiano.
- **Limite dei canali**: il client ammette al massimo 10 canali (da confermare su Forever). Se il personaggio ne ha già 10 l'addon **non chiede** l'entrata (stamperebbe un errore nella chat a ogni tentativo), avvisa **una sola volta** (`/leave` di un canale qualsiasi) e riprova ogni 60 s.
- **Eventi sul Bus**: `CHANNEL_READY(id)` e `CHANNEL_FAILED(reason)` con `reason` = `limit`, `throttled`, `banned`, `refused`, `timeout`, `unavailable` (nessuna funzione di entrata: non si riprova) o `left`; lo stesso motivo non viene ripetuto a ogni tentativo. Al nuovo `CHANNEL_READY` il `Transport` esce dal modo solo ascolto.

## 2. Formato dei messaggi

```
payload = EncodeBase64( [flag] .. (compresso ? CompressString(CBOR(msg)) : CBOR(msg)) )
msg     = { v = PROTO, t = "<TIPO>", ... campi del tipo ... }
```

- Si comprime solo sopra i 120 byte; il primo byte indica se il messaggio è compresso.
- I campi sconosciuti vengono **ignorati**, per compatibilità con le versioni future.
- Un `v` maggiore di `PROTO` viene ignorato, e una sola volta per sessione l'addon avvisa "A newer version of Azeroth Guild Finder is available".
- I messaggi malformati o troppo grandi (> 8 KB decompressi) vengono scartati senza errori a schermo; vanno solo nella diagnostica di `/gf debug`.

## 3. Tipi di messaggio

| Tipo | Canale | Da → a | Contenuto | Quando |
|---|---|---|---|---|
| `ANN` | CHANNEL | membro della gilda → tutti | riassunto dell'annuncio + statistiche + ruolo del mittente (`c=1` se è un contatto: GM o ufficiale) | periodicamente e dopo ogni modifica (§5) |
| `DEL` | CHANNEL | GM o membro → tutti | ritiro dell'annuncio `{k, rev}` | quando il GM ritira l'annuncio |
| `CATREQ` | CHANNEL | qualsiasi → tutti | elenco compatto del proprio catalogo `[{h, rev, srev}]` + `nonce` | all'entrata nel canale (§6) |
| `CATACK` | CHANNEL | chi risponde → tutti | `{to, nonce}`: "rispondo io" | prima di inviare `CAT` |
| `CAT` | WHISPER | chi risponde → richiedente | riassunti mancanti o più recenti | risposta a `CATREQ` |
| `DETREQ` | CHANNEL | qualsiasi → tutti | `{k, rev, nonce}` | quando si apre una pagina della gilda senza il dettaglio in cache |
| `DETACK` | CHANNEL | chi risponde → tutti | `{to, nonce}` | prima di inviare `DET` |
| `DET` | WHISPER | chi risponde → richiedente | dettaglio dell'annuncio | risposta a `DETREQ` |
| `GLIST` | GUILD | GM → membri | annuncio completo (riassunto + dettaglio) | pubblicazione, modifica, ritiro, risposta a `GLREQ` |
| `GLREQ` | GUILD | membro → gilda | `{rev}` posseduto | al login, se l'annuncio manca o è vecchio |
| `GTOK` | GUILD | membro → gilda | token anonimo dell'account per quella gilda | al login e ogni 24 h ([SPEC-03 §4](SPEC-03-data-model.md#4-statistiche)) |
| `APPLY` | WHISPER | candidato → contatto | candidatura | clic su Candidati e nuovi tentativi ([SPEC-07](SPEC-07-applications.md)) |
| `APPACK` | WHISPER | contatto → candidato | `{id, state}` | ricezione di `APPLY` o `APPPING` |
| `APPPING` | WHISPER | candidato → contatto | `{id}` | quando vede online un contatto della gilda |
| `APPWD` | WHISPER | candidato → contatto | ritiro `{id}` | il candidato ritira la candidatura |
| `APPSYNC` | OFFICER | ufficiale ↔ ufficiale | elenco compatto `{id: stateRev}` e record mancanti | al login e dopo ogni cambio |
| `PING` | CHANNEL | qualsiasi → tutti | `{nonce}`: **messaggio di diagnostica** | solo `/gf debug ping` (M1.8) |
| `PONG` | WHISPER | chi risponde → mittente del `PING` | `{nonce}` | risposta a un `PING` |

`PING` e `PONG` sono messaggi di **diagnostica**, non fanno parte del catalogo: servono a verificare che due installazioni si sentano sul canale (criterio di uscita di M1). `/gf debug ping` invia un `PING` (al massimo uno ogni 10 s per client), raccoglie i `PONG` per 5 s e stampa **quanti** peer hanno risposto e i tempi di andata e ritorno (minimo, medio, massimo), mai i nomi: i peer vengono contati una volta sola tramite un hash a 32 bit che vive solo fino alla stampa del risultato. Ogni client risponde a un solo `PING` ogni 5 s e mai al proprio (il canale rimanda i propri messaggi), così una raffica di `PING` non costa niente agli altri.

Il dettaglio (descrizione e contatti) **non** viaggia negli `ANN`: la lista ha bisogno solo dei riassunti, e i dettagli si scaricano quando si apre la pagina.

## 4. Priorità e limiti di traffico

| Priorità ChatThrottleLib | Messaggi |
|---|---|
| `ALERT` | `APPLY`, `APPACK`, `APPWD`, `CATACK`, `DETACK`, `PING`, `PONG` (diagnostica) |
| `NORMAL` | `DET`, `GLIST`, `APPSYNC`, `DEL` |
| `BULK` | `ANN`, `CAT`, `CATREQ`, `GTOK` |

Limiti per client (MUST):

- **NET-01** Nel canale, al massimo 1 messaggio ogni `CHANNEL_GAP` e in media non più di 2 KB al minuto, escluse le risposte alle richieste esplicite.
- **NET-02** Al massimo una risposta `CAT` e tre risposte `DET` per minuto.
- **NET-03** Nessun invio durante `InChatMessagingLockdown()` o le restrizioni degli addon: i messaggi restano in coda. In coda resta solo l'ultimo `ANN` per gilda, e i messaggi `BULK` più vecchi di 10 minuti vengono scartati.
- **NET-04** Se il server segnala un eccesso di traffico, si riprova dopo 4×`CHANNEL_GAP`, per un massimo di 3 tentativi.

## 5. Annunci periodici (`ANN`)

- Ogni membro della gilda con l'addon e con l'annuncio della propria gilda pubblicato prepara un `ANN` ogni **30 min ± 10 min** (ritardo casuale).
- **Soppressione**: se nel frattempo è arrivato un `ANN` della stessa gilda con `rev` e `srev` uguali o maggiori, il proprio salta un turno. Così una gilda con 40 membri online produce circa un annuncio ogni 30 minuti, non 40.
- Il GM invia subito un `ANN` dopo la pubblicazione o una modifica. I membri lo inviano subito dopo aver ricevuto un `GLIST` più recente, ma solo dopo un ritardo casuale di 5–30 s con soppressione.
- Gli `ANN` dei GM e degli ufficiali (`c=1`) servono anche a far sapere ai candidati **quali contatti sono online** ([SPEC-07](SPEC-07-applications.md)).

## 6. Sincronizzazione del catalogo (`CATREQ` / `CAT`)

1. Pronto il canale, il client attende un tempo casuale tra 5 e 15 s, poi invia `CATREQ`, a meno che l'ultima sincronizzazione completa sia di meno di 10 minuti prima.
2. `CATREQ` contiene, per ogni annuncio conosciuto, `h` (hash a 32 bit della chiave della gilda), `rev` e `srev`. Con 100 gilde sono circa 1 KB, cioè 4–5 pezzi.
3. Ogni peer che ha qualcosa di nuovo per il richiedente programma una risposta dopo un ritardo casuale tra 0,5 e 5 s: più breve se ha molto da inviare o ha sincronizzato da poco.
4. Il primo che scade invia `CATACK{to, nonce}` nel canale; gli altri, vedendolo, annullano la propria risposta.
5. Il vincitore invia in `WHISPER` i riassunti mancanti o più recenti, in ordine alfabetico, a gruppi di 10. L'interfaccia si aggiorna a ogni gruppo.
6. Se in 20 s non arriva niente, il richiedente riprova dopo 60 s, al massimo 3 volte; poi resta in ascolto degli `ANN`.

`DETREQ` / `DETACK` / `DET` seguono lo stesso schema per un singolo dettaglio. Il dettaglio è richiesto solo se manca o se la sua `rev` è inferiore a quella del riassunto.

## 7. Sincronizzazione nella gilda

- **GLIST**: è il GM l'autore. I membri accettano un `GLIST` solo se arriva sul canale `GUILD`, che il server consegna solo ai membri, **e** se il mittente è il capo della gilda secondo il roster (grado 0, `GetGuildRosterInfo` [verificare]). Questa è l'unica fonte di un annuncio di cui ci si possa fidare davvero.
- **GLREQ**: chi entra senza annuncio o con una `rev` vecchia lo chiede. Risponde il GM, oppure qualsiasi membro con la `rev` più recente, con la stessa soppressione del §6, perché il GM spesso non è online.
- **APPSYNC** (OFFICER): ogni ufficiale e il GM tengono una copia della casella delle candidature. All'entrata in gioco si scambiano l'elenco compatto e si inviano i record mancanti; per ogni record vince la versione con lo `stateRev` più alto ([SPEC-07 §4](SPEC-07-applications.md#4-sincronizzazione-tra-ufficiali)). Se `OFFICER` non fosse accettato come canale per gli addon [verificare], si userebbe `GUILD` e chi non è ufficiale ignorerebbe i messaggi. È peggio per la riservatezza, quindi va deciso dopo lo spike.

## 8. Integrità e limiti del modello P2P

Senza un server, chiunque abbia l'addon modificato può inviare un `ANN` falso. Gli strumenti disponibili in Lua puro (nessuna firma digitale nativa) permettono una protezione **ragionevole, non crittografica**.

| Regola | Effetto |
|---|---|
| **INT-01** Ordine per `(rev, updatedAt)`; a parità vince l'hash del contenuto più basso, per una scelta deterministica | tutti i client convergono sulla stessa versione |
| **INT-02** `GLIST` accettato solo da `GUILD` e dal capo della gilda secondo il roster | i membri hanno sempre la versione vera della propria gilda |
| **INT-03** `ownerId`: identificativo casuale creato dal GM alla prima pubblicazione. Un annuncio con un `ownerId` diverso da quello conosciuto viene ignorato, a meno che quello conosciuto non riceva `ANN` da 30 giorni (per esempio dopo un cambio di GM che ha ricreato l'annuncio) | evita i conflitti accidentali; **non** ferma un attacco voluto, perché l'`ownerId` è pubblico |
| **INT-04** Un mittente che in 24 h fa `ANN` per **più di una gilda** viene ignorato nel canale fino al giorno dopo (le risposte `CAT` viaggiano in WHISPER e non contano) | un falsificatore deve usare un personaggio per ogni gilda falsa |
| **INT-05** Un `DEL` è accettato solo da un mittente che in passato ha fatto `ANN` per la stessa gilda; se dopo arriva un `ANN` con `rev` maggiore, l'annuncio ritorna | limita i ritiri falsi |
| **INT-06** Validazione completa di ogni campo ([SPEC-03 §6](SPEC-03-data-model.md#6-validazione)); i testi non vengono mai eseguiti né interpretati come codici di formattazione (`|` viene neutralizzato) | niente link o colori iniettati, niente errori Lua |

Come le applica `Data/Catalog.lua` (M2.2), dove le regole lasciano margine:

- **INT-01**: l'ordine riguarda il contenuto; le statistiche (`st`, `srev`) si fondono a parte, vince lo `srev` più recente (a parità, l'hash più basso), anche se arrivano in un riassunto di `rev` più vecchia. Per questo, a parità di aggiornamenti ricevuti, l'ordine di arrivo non cambia l'elenco.
- **INT-03**: vale il primo `ownerId` conosciuto, quindi due `ownerId` in conflitto non convergono sullo stesso client finché il primo non tace da 30 giorni. Solo un `ANN` accettato (stesso `ownerId`, anche di `rev` più vecchia) rinnova il momento dell'ultimo annuncio.
- **INT-04**: si applica solo agli `ANN` e ai `DEL` che arrivano nel canale; il divieto dura 24 h dal secondo annuncio e comprende anche i `DEL` e gli `ANN` della prima gilda. Un annuncio rifiutato per `ownerId` conta comunque come annuncio di quella gilda.
- **INT-05**: chi ha annunciato una gilda si ricorda solo in memoria (mai nel file, per riservatezza): dopo un `/reload` un `DEL` viene accettato di nuovo solo da chi annuncia ancora. Il `DEL` ritira le `rev` fino a quella indicata; l'`ANN` con `rev` maggiore riporta l'annuncio. Gli annunci ritirati non vengono mai offerti agli altri in un `CAT`.

Rischio residuo, accettato per la V1: un attaccante determinato può falsificare l'annuncio di **una** gilda per personaggio. Se succede davvero, la V2 introdurrà la firma degli annunci (Ed25519 in Lua puro, chiave del GM condivisa con gli ufficiali via `GUILD`) con un nuovo `PROTO`.
