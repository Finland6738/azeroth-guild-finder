# SPEC-09: Qualità, spike e rilascio

## 1. Spike tecnico (M0)

Prima di scrivere l'addon vero si prepara un **addon di prova** (`AzGF_Probe`, non distribuito), da usare in gioco con due account o con l'aiuto di un altro giocatore. Ogni punto ha un esito che può cambiare le specifiche.

| # | Verifica | Se va male |
|---|---|---|
| S1 | `C_ClubFinder.IsEnabled()`, `ShouldShowClubFinder()`, `GetClubFinderDisableReason()` | se il cercagilde di Blizzard **è attivo**, va rivista l'architettura: catalogo lato server, niente P2P |
| S2 | Entrata in `AzGuildFinder` con `JoinChannelByName`, invio e ricezione di `SendAddonMessage(..., "CHANNEL", id)` tra due client | se fallisce, non c'è un catalogo pubblico: si ripiega su YELL o su relay di gilda (da progettare) |
| S3 | **Livello minimo per inviare nel canale**: prova con personaggi di livello 1, 5, 10, 20 e un account nuovo | determina quanto è ampio il modo solo ascolto (SPEC-01 §8) |
| S4 | `WHISPER` di addon verso un personaggio non amico, anche da un personaggio di livello basso | se fallisce, la candidatura dei personaggi bassi va ripensata |
| S5 | `OFFICER` come canale per gli addon | se fallisce, `APPSYNC` passa in `GUILD` (SPEC-02 §7) |
| S6 | Throttle reale del canale: messaggi al secondo prima di ricevere `ChannelThrottle` / `AddonMessageThrottle` | aggiorna `CHANNEL_GAP` e il budget di NET-01 |
| S7 | Globali della gilda: `GetGuildInfo`, `GetNumGuildMembers`, `GetGuildRosterInfo`, `GetGuildRosterLastOnline`, `GetMaxPlayerLevel`, `GetAverageItemLevel` | se mancano, si usano `C_Club.GetMemberInfo` (`ClubMemberInfo.lastOnline*`) |
| S8 | `C_GuildInfo.GetGuildTabardInfo("player")`: campi reali; `TabardModel` + `CycleVariation`: catalogo dei fileID di emblemi, bordi, sfondi e colori (`/gf debug tabard`) | se `CycleVariation` non funziona fuori dal negozio dei tabarri, il catalogo si ricava dai tabarri delle gilde visti negli `ANN` e da un elenco di fileID noti |
| S9 | Galleria degli sfondi e pergamena (SPEC-08 §3), icone di classi e ruoli | si sostituiscono le immagini che non passano |
| S10 | `C_GuildInfo.Invite` chiamato dal clic su un pulsante dell'addon (protetto o no?) | se è protetto, Invite apre la chat con `/ginvite Nome` precompilato |
| S11 | Comportamento durante `InChatMessagingLockdown` (istanze, incontri, PvP) | adatta NET-03 |

I risultati si registrano in `docs/spike/M0-results.md` e le decisioni che cambiano le specifiche diventano ADR.

## 2. Test offline

Lo stesso approccio di azeroth-unspoken (ADR 0007): Lua 5.1 con un **finto ambiente WoW** (API di gilda, chat, timer, SavedVariables).

| Area | Cosa si verifica |
|---|---|
| `Normalize` | chiavi di ordinamento (accenti, simboli, numeri), ricerca con meno di 3 lettere |
| `Codec` | andata e ritorno CBOR + compressione + Base64; messaggi rovinati scartati senza errori |
| `Sanitize` | ogni campo fuori dai limiti; testo con `|`, caratteri di controllo, UTF-8 lungo |
| `Catalog` | INT-01…INT-05, scadenze, unione dei riassunti e dei dettagli |
| `Sync` | **simulatore con N client** su un canale finto: convergenza del catalogo, numero di messaggi (soppressione), perdita di messaggi, client in solo ascolto |
| `Stats` | `a7`, intervalli di `u7` con copertura parziale |
| `Applications` | tutte le transizioni di stato, APP-01…APP-06, conflitti di `APPSYNC` |
| `Config` | migrazioni dello schema, dati di una versione più recente in sola lettura |

Obiettivo: il simulatore con 50 client e 100 gilde converge in meno di 5 minuti simulati, senza superare NET-01.

**Il simulatore** (`Tests/sim/sim.lua`, M1.8) fa girare N copie complete dell'addon, ognuna con il proprio ambiente di gioco, il proprio finto client (orologio, timer, chat, gilda) e le proprie SavedVariables, su un orologio condiviso. Instrada `CHANNEL` (a tutti i client nel canale, compreso il mittente come fa il gioco), `WHISPER` (al destinatario), `GUILD` (alla stessa gilda) e `OFFICER` (agli ufficiali della stessa gilda), con latenza configurabile (fissa o in un intervallo), perdita di messaggi (probabilità o funzione) e restrizioni per client (solo ascolto, blocco della chat, addon in sola lettura, offline). `sim:stats()` dà messaggi e byte inviati per client e per minuto (e il minuto più carico sul canale) per verificare NET-01. Come scrivere un test: [CONTRIBUTING §4](../../CONTRIBUTING.md#4-checks-and-tests).

## 3. Prove in gioco (prima di ogni rilascio)

Un elenco di controllo in `docs/checklists/release.md`:

- tutti i ruoli della matrice di SPEC-00 §5, con il cambio di ruolo a finestra aperta;
- annuncio pubblicato → visibile da un secondo client senza gilda in meno di 2 minuti;
- candidatura con l'ufficiale online / offline / che arriva dopo;
- `/reload` e logout con la candidatura aperta;
- combattimento, istanza, campo di battaglia: niente errori e niente invii;
- scala dell'interfaccia al 64 % e al 115 %, risoluzione 1280 × 720.

## 4. Pacchetti e rilascio (D3, D24)

- **Versioni** semantiche: `v0.x` per le prove con pochi utenti, `v1.0.0` per la V1. Il TOC usa `## Version: @project-version@`.
- **Pacchetti** creati con il BigWigs Packager in una GitHub Action al push di un tag: pubblica su **GitHub Releases** e su **CurseForge** (servono l'ID del progetto e il token nei segreti del repository).
- `.pkgmeta`: librerie esterne (Ace3, LibDBIcon, LibDataBroker) a versioni fissate; esclusi `Tests/`, `docs/`, `.idea/`.
- Pagina CurseForge e README con: cos'è, come si installa a mano, che è **non ufficiale**, quali dati condivide (catalogo pubblico; nella gilda solo token anonimi) e i limiti del modello P2P.
- Licenza del codice: da scegliere ([SPEC-10](SPEC-10-risks-open-questions.md)).

## 5. Tappe

Gli step di sviluppo di ogni tappa sono in [docs/roadmap/](../roadmap/README.md), un file per tappa.

| Tappa | Contenuto | Uscita |
|---|---|---|
| M0 | Spike S1–S11, bozzetti approvati | risultati + ADR |
| M1 | Struttura dell'addon, Compat, Config, Codec, Transport, Channel, test offline | messaggi tra due client |
| M2 | Catalog, Sync, Normalize; Trova gilda (lista, ricerca, filtri) con dati di prova | lista sincronizzata |
| M3 | Editor, My Guild, stemmi, sfondi, statistiche | annuncio pubblicato da un GM vero |
| M4 | Candidature, pannello, icona di notifica, My Application | flusso completo |
| M5 | Rifinitura, impostazioni, prove in gioco, pacchetti | `v0.9` beta su GitHub |
| — | Beta con alcune gilde vere, correzioni | `v1.0.0` su CurseForge |
