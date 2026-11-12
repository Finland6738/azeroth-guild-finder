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
| `ANN` | CHANNEL | membro della gilda → tutti | riassunto dell'annuncio + statistiche + ruolo del mittente (`c=1` se è un contatto: GM o ufficiale); `test=true` per l'annuncio di prova di `/gf debug announce` | periodicamente e dopo ogni modifica (§5) |
| `DEL` | CHANNEL | GM o membro → tutti | ritiro dell'annuncio `{k, rev}` | quando il GM ritira l'annuncio |
| `CATREQ` | CHANNEL | qualsiasi → tutti | `nonce` + elenco compatto del proprio catalogo `cat = {h1, rev1, srev1, h2, …}`; un catalogo grande va in più parti `p`/`n` con lo stesso `nonce` | all'entrata nel canale (§6) |
| `CATACK` | CHANNEL | chi risponde → tutti | `{to, nonce, n, w}`: "rispondo io", con `n` riassunti da inviare (0 = "non hai niente di vecchio") e `w` secondi di attesa per NET-02 | prima di inviare `CAT` |
| `CAT` | WHISPER | chi risponde → richiedente | `{nonce, items, age, i, of, n}`: fino a 10 riassunti mancanti o più recenti, l'età del loro ultimo `ANN`, il numero del gruppo e il totale | risposta a `CATREQ` |
| `DETREQ` | CHANNEL | qualsiasi → tutti | `{k, rev, d, nonce}`: `rev` del riassunto posseduto, `d` del dettaglio posseduto (0 = nessuno) | quando si apre una pagina della gilda senza il dettaglio in cache |
| `DETACK` | CHANNEL | chi risponde → tutti | `{to, nonce, r}`: `r` = `rev` del dettaglio che invierà | prima di inviare `DET` |
| `DET` | WHISPER | chi risponde → richiedente | dettaglio dell'annuncio + `nonce` | risposta a `DETREQ` |
| `GLIST` | GUILD | GM → membri | annuncio completo (riassunto + dettaglio); `del=true` se ritirato | pubblicazione, modifica, ritiro, risposta a `GLREQ` |
| `GLREQ` | GUILD | membro → gilda | `{rev}` posseduto (0 = nessuno) | al login, se l'annuncio manca o è vecchio |
| `GTOK` | GUILD | membro → gilda | token anonimo dell'account per quella gilda | al login e ogni 24 h ([SPEC-03 §4](SPEC-03-data-model.md#4-statistiche)) |
| `APPLY` | WHISPER | candidato → contatto | candidatura | clic su Candidati e nuovi tentativi ([SPEC-07](SPEC-07-applications.md)) |
| `APPACK` | WHISPER | contatto → candidato | `{id, state}` | ricezione di `APPLY` o `APPPING` |
| `APPPING` | WHISPER | candidato → contatto | `{id}` | quando vede online un contatto della gilda |
| `APPWD` | WHISPER | candidato → contatto | ritiro `{id}` | il candidato ritira la candidatura |
| `APPSYNC` | OFFICER | ufficiale ↔ ufficiale | record cambiati `{k, recs}`; elenco compatto `{k, q=1, ids = {id: versione}}`; risposta `{k, to, ids}` con gli id diversi; richiesta `{k, to, want}` ([SPEC-07 §4](SPEC-07-applications.md#4-sincronizzazione-tra-ufficiali)) | al login e dopo ogni cambio |
| `PING` | CHANNEL | qualsiasi → tutti | `{nonce}`: **messaggio di diagnostica** | solo `/gf debug ping` (M1.8) |
| `PONG` | WHISPER | chi risponde → mittente del `PING` | `{nonce}` | risposta a un `PING` |

`PING` e `PONG` sono messaggi di **diagnostica**, non fanno parte del catalogo: servono a verificare che due installazioni si sentano sul canale (criterio di uscita di M1). `/gf debug ping` invia un `PING` (al massimo uno ogni 10 s per client), raccoglie i `PONG` per 5 s e stampa **quanti** peer hanno risposto e i tempi di andata e ritorno (minimo, medio, massimo), mai i nomi: i peer vengono contati una volta sola tramite un hash a 32 bit che vive solo fino alla stampa del risultato. Ogni client risponde a un solo `PING` ogni 5 s e mai al proprio (il canale rimanda i propri messaggi), così una raffica di `PING` non costa niente agli altri.

Il dettaglio (descrizione e contatti) **non** viaggia negli `ANN`: la lista ha bisogno solo dei riassunti, e i dettagli si scaricano quando si apre la pagina.

## 4. Priorità e limiti di traffico

| Priorità ChatThrottleLib | Messaggi |
|---|---|
| `ALERT` | `APPLY`, `APPACK`, `APPPING`, `APPWD`, `CATACK`, `DETACK`, `PING`, `PONG` (diagnostica) |
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
- Gli `ANN` dei GM e degli ufficiali (`c=1`) servono anche a far sapere ai candidati **quali contatti sono online** ([SPEC-07](SPEC-07-applications.md)). Per questo il turno di un contatto salta solo per l'`ANN` di un altro contatto (`c=1`), non per quello di un membro (M4.2): una gilda con 40 membri e 3 ufficiali online produce uno o due `ANN` ogni 30 minuti, almeno uno di un contatto.
- `Net/Sync.lua` (M2.3) riceve `ANN` e `DEL` solo dal canale e li passa al catalogo con il mittente (INT-04, INT-05). Ricorda **solo in memoria** i contatti (`c=1`) di ogni gilda con l'ora in cui li ha sentiti (al massimo 10 per gilda, per M4) e l'ultimo `ANN` di ogni gilda sentito da **un altro** client (`rev`, `srev`, ora; il proprio `ANN` rimandato dal canale non conta): `Sync:Suppressed(k, rev, srev, since, contact)` dice se il proprio `ANN` periodico deve saltare il turno (con `contact` conta solo l'ultimo `ANN` con `c=1`). Per ogni `ANN` accettato con `c=1` di un altro client il Bus riceve `CONTACT_SEEN(k, mittente)` (M4.2). `Sync:Announce(riassunto, {contact, test})` mette in coda un `ANN` (BULK, solo l'ultimo per gilda).
- **Invio periodico** (`Data/OwnListing.lua`, M3.7): ogni client in una gilda ha un turno armato con un ritardo estratto di nuovo a ogni turno tra 20 e 40 minuti (`ANN_PERIOD`); il turno parte all'entrata in gioco o nella gilda (una promozione non lo riarma) e si ferma senza gilda. Al turno il client annuncia la copia della gilda solo se è pubblicata (non ritirata), con le statistiche di `Data/Stats.lua` e `c=1` se è il GM o un ufficiale; salta il turno se, da quando il turno è stato armato, ha sentito da un altro client un `ANN` della stessa gilda con `rev` e `srev` uguali o maggiori (il GM e gli ufficiali solo un `ANN` con `c=1`, `Sync:Suppressed(..., contact)`). Poiché `srev` cambia una volta all'ora, dopo ogni cambio d'ora il primo turno che scade porta le statistiche nuove. Nel simulatore 5 membri con turni ridotti a 20–40 s inviano circa un `ANN` per turno invece di cinque (`Tests/test_stats.lua`).

## 6. Sincronizzazione del catalogo (`CATREQ` / `CAT`)

1. Pronto il canale, il client attende un tempo casuale tra 5 e 15 s, poi invia `CATREQ`, a meno che l'ultima sincronizzazione completa sia di meno di 10 minuti prima.
2. `CATREQ` contiene, per ogni annuncio conosciuto, `h` (hash a 32 bit della chiave della gilda), `rev` e `srev`. Con 100 gilde sono circa 1 KB, cioè 4–5 pezzi.
3. Ogni peer che ha qualcosa di nuovo per il richiedente programma una risposta dopo un ritardo casuale tra 0,5 e 5 s: più breve se ha molto da inviare o ha sincronizzato da poco.
4. Il primo che scade invia `CATACK{to, nonce}` nel canale; gli altri, vedendolo, annullano la propria risposta.
5. Il vincitore invia in `WHISPER` i riassunti mancanti o più recenti, in ordine alfabetico, a gruppi di 10. L'interfaccia si aggiorna a ogni gruppo.
6. Se in 20 s non arriva niente, il richiedente riprova dopo 60 s, al massimo 3 volte; poi resta in ascolto degli `ANN`.

`DETREQ` / `DETACK` / `DET` seguono lo stesso schema per un singolo dettaglio. Il dettaglio è richiesto solo se manca o se la sua `rev` è inferiore a quella del riassunto.

### 6.1 Come lo fa `Net/Sync.lua` (M2.3)

Dove le regole sopra lasciano margine, l'addon fa così (i numeri sono campi di `Sync` e i test li possono cambiare):

- **Digest**: `cat` è una lista piatta di interi `h, rev, srev` per ogni annuncio conosciuto (anche quelli ritirati, così nessuno li rimanda), in ordine A→Z, a parti di 64 annunci (`p`/`n`, al massimo 16 parti). Chi risponde aspetta tutte le parti; una richiesta incompleta viene dimenticata dopo 60 s. Con 100 gilde il digest è di circa 1,1 KB prima della compressione: due parti.
- **Elezione**: ogni peer che ha qualcosa calcola `n` (i riassunti da inviare) e programma il `CATACK` nella finestra 0,5–5 s: prima i peer liberi, con un ritardo più breve se `n` è grande (fino a 100) e se la propria sincronizzazione completa è recente; poi (3,5–4,2 s) chi deve aspettare il proprio turno di NET-02, il meno occupato per primo; per ultimi (4,2–5 s) i "niente di nuovo" (`n=0`), solo da chi ha finito una sincronizzazione completa negli ultimi 30 minuti e solo circa 3 di loro. Dentro ogni fascia il ritardo segue una distribuzione esponenziale (Nonnenmacher-Biersack) calcolata su almeno 32 peer, così pochi timer scadono entro la latenza del primo.
- **Conferma**: chi ha inviato il `CATACK` aspetta 1 s; se nel frattempo vede un `CATACK` migliore per la stessa richiesta si ritira. Migliore = chi può inviare prima (attesa `w` più corta di oltre 5 s), poi chi ha più riassunti, poi l'hash del nome più basso. Il richiedente usa la stessa regola per sapere da chi aspettare i `CAT`. Chi non ha ancora inviato il proprio `CATACK` e ne vede uno lo annulla, a meno che quello dica "niente di nuovo" mentre lui ha qualcosa, o che chi lo ha inviato debba aspettare molto più di lui.
- **NET-02**: le risposte `CAT` di un client sono in fila, una al minuto (61 s): il `CATACK` dichiara in `w` quanto manca al proprio turno, contando anche le risposte promesse e non ancora inviate, e il richiedente aspetta `1 + w + 10` s il primo gruppo. I gruppi di una risposta contano come una sola risposta nel `Transport` (`rateGroup`).
- **Turni**: un turno che ha portato qualcosa di nuovo è seguito da un altro `CATREQ` dopo 1–3 s (un altro peer può sapere di più), al massimo 8 turni. La sincronizzazione è completa quando un turno non porta niente di nuovo, quando arriva un `CATACK` con `n=0` e nessuno migliore entro 2 s, o quando due turni successivi al primo restano senza risposta per 20 s (un solo silenzio può essere una perdita). Un turno con un `CATACK` ma senza nessun `CAT` (per 10 s dopo l'ultimo gruppo o dopo l'attesa dichiarata) viene ripetuto, e conta tra i 3 tentativi. L'ora dell'ultima sincronizzazione completa è salvata in `AzerothGuildFinderDB.syncAt["realm|faction"]`.
- **Solo ascolto**: se il canale rifiuta i messaggi (`InvalidChannel`, M1.7) il `CATREQ` e il `DETREQ` partono in `WHISPER` verso l'ultimo peer sentito nel canale (o un contatto della gilda per il dettaglio); se non ne conosce nessuno aspetta il primo messaggio del canale. Chi riceve una richiesta in `WHISPER` risponde direttamente, senza elezione, con `CATACK` e `CAT` in `WHISPER`. Un client in solo ascolto non partecipa alle elezioni del canale.
- **Dettagli**: `Sync:RequestDetail(k)` invia `DETREQ` se il dettaglio manca o è più vecchio del riassunto; risponde chi ha un dettaglio con `d < rev ≤ rev del riassunto` del richiedente (prima chi ha esattamente quella `rev`), al massimo tre `DET` al minuto. Dopo 20 s senza dettaglio il Bus riceve `DETAIL_UNAVAILABLE(k)`.
- **Annuncio di prova**: `/gf debug announce` funziona solo nelle build di sviluppo (`Config.DEV`, vero in una copia del repository: il packager commenta il blocco `--@debug@` nelle build pubblicate). Invia un `ANN` con `test=true` per la gilda *AGF Test &lt;personaggio&gt;* (`ownerId` derivato dal segreto dell'account, `rev` = ora del server) e ne tiene il dettaglio per i `DETREQ`. Le build di rilascio ignorano gli `ANN` e i riassunti `CAT` con `test=true`.

**Misure nel simulatore** (`Tests/test_sync_sim.lua`, latenza 0,05–0,3 s, nessuna perdita salvo dove indicato):

| Scenario | Risultato |
|---|---|
| 50 client, 100 gilde: 5 client con il catalogo completo, 45 entrano insieme con un quarto del catalogo e un decimo vecchio, 10 gilde inviano un `ANN` nuovo durante la prova | tutti identici dopo **200 s**; nel minuto peggiore un client invia 14 messaggi nel canale e 2040 byte di richieste e annunci (limite NET-01: 2048); 153 risposte `CAT`, 782 `CATACK` (risposte, fuori dal limite di byte), nessun gruppo `CAT` doppio |
| Lo stesso senza i 5 client completi (avvio a freddo, ognuno con un terzo sparso; misurato durante lo sviluppo, non è nella suite) | circa **290 s**: il limite è NET-02 (ogni peer risponde una volta al minuto e servono circa cinque turni) |
| Un client entra dopo 19 client già sincronizzati (100 gilde) | catalogo completo in **15 s** da **un solo** peer (10 gruppi `CAT`), 3 `CATACK` in tutto |
| 20 client, 60 gilde (2 con il catalogo completo, gli altri con il 30 %), 10 % dei messaggi persi | tutti identici in **275 s** (le richieste perse aspettano i nuovi tentativi) |

## 7. Sincronizzazione nella gilda

- **GLIST**: è il GM l'autore. I membri accettano un `GLIST` solo se arriva sul canale `GUILD`, che il server consegna solo ai membri, **e** se il mittente è il capo della gilda secondo il roster (grado 0, `GetGuildRosterInfo` [verificare]). Questa è l'unica fonte di un annuncio di cui ci si possa fidare davvero.
- **GLREQ**: chi entra senza annuncio o con una `rev` vecchia lo chiede. Risponde **solo il GM** ([ADR 0021](../adr/0021-guild-copy-of-the-listing-from-the-guild-master-only.md)): la risposta di un membro verrebbe comunque rifiutata da INT-02. Se il GM non è online, il membro senza copia vede l'annuncio solo nel catalogo pubblico.

### 7.1 Come lo fa `Data/OwnListing.lua` (M3.1)

Dove le regole sopra lasciano margine ([ADR 0021](../adr/0021-guild-copy-of-the-listing-from-the-guild-master-only.md); i numeri sono campi di `OwnListing` e i test li possono cambiare):

- **Controllo del GM**: il mittente di un `GLIST` deve essere, per nome senza il suffisso del reame, il membro di grado 0 del roster (`Compat.Guild.LeaderName`). Se il roster non è ancora caricato, il `GLIST` più recente aspetta fino a 30 s il `GUILD_ROSTER_UPDATE` (l'addon lo chiede con `C_GuildInfo.GuildRoster`), poi viene controllato o scartato. I propri `GLIST` rimandati dal server vengono ignorati.
- **Copia della gilda**: ogni personaggio tiene in `ownListing.published` l'ultima copia accettata, ordinata come INT-01 (`rev`, poi `upd`, poi l'hash del contenuto). La copia nuova entra anche nel catalogo locale (riassunto e dettaglio; se ritirata, la lapide del `DEL`).
- **Ripetizione nel canale**: il membro che accetta una copia più recente invia un `ANN` dopo 5–30 s, a meno che negli ultimi 60 s abbia sentito un `ANN` della stessa `rev` (un ufficiale mette `c=1`). Una copia ritirata viene ripetuta come `DEL` solo da chi ha annunciato la gilda in questa sessione (INT-05).
- **GLREQ**: al login e quando il catalogo pubblico mostra una `rev` più recente della copia, dopo 3–10 s, a meno che nel frattempo arrivi un `GLIST` o il `GLREQ` di un altro membro con la stessa `rev` o una più vecchia; al massimo uno ogni 5 minuti; un `GLREQ` ancora in coda viene annullato se nel frattempo arriva una di queste due cose. Il GM raccoglie le richieste per 2 s e risponde con un solo `GLIST`, al massimo uno ogni 30 s.

- **APPSYNC** (OFFICER): ogni ufficiale e il GM tengono una copia della casella delle candidature. All'entrata in gioco si scambiano l'elenco compatto e si inviano i record mancanti; per ogni record vince la versione con lo `stateRev` più alto ([SPEC-07 §4](SPEC-07-applications.md#4-sincronizzazione-tra-ufficiali)). Se `OFFICER` non fosse accettato come canale per gli addon [verificare], si userebbe `GUILD` e chi non è ufficiale ignorerebbe i messaggi. È peggio per la riservatezza, quindi va deciso dopo lo spike. Nel M4.3 (`Net/InboxSync.lua`) il ripiego è una sola costante, `InboxSync.DIST`; con `GUILD` un messaggio conta solo se il grado del mittente nel roster legge la chat degli ufficiali. Il dettaglio dei messaggi, della versione dei record e dei limiti è nella nota di realizzazione di [SPEC-07 §4](SPEC-07-applications.md#4-sincronizzazione-tra-ufficiali).

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
- **INT-05**: chi ha annunciato una gilda si ricorda solo in memoria (mai nel file, per riservatezza): dopo un `/reload` un `DEL` viene accettato di nuovo solo da chi annuncia ancora. Il `DEL` ritira le `rev` fino a quella indicata; l'`ANN` con `rev` maggiore riporta l'annuncio. Gli annunci ritirati non vengono mai offerti agli altri in un `CAT`. Solo nel catalogo locale, il ritiro della propria gilda (fatto dal GM o arrivato con un `GLIST` del GM del roster, M3.1) non ha bisogno di questa regola (`meta.trusted`).

Rischio residuo, accettato per la V1: un attaccante determinato può falsificare l'annuncio di **una** gilda per personaggio. Se succede davvero, la V2 introdurrà la firma degli annunci (Ed25519 in Lua puro, chiave del GM condivisa con gli ufficiali via `GUILD`) con un nuovo `PROTO`.
