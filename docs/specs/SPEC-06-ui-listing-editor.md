# SPEC-06: Editor dell'annuncio e "My Guild"

## 1. Chi lo vede

- **GM senza annuncio**: vede solo l'editor ("Create Listing").
- **GM con annuncio**: vede "My Guild", la pagina della gilda con i pulsanti **Edit listing** e **Delist**, più "Applications".
- **Ufficiali e membri**: vedono "My Guild" in sola lettura (bozzetto [`06-states.webp`](mockups/img/06-states.webp)). Nessuno tranne il GM effettivo può modificare (D14).

Prima di salvare o pubblicare, l'addon **ricontrolla** `IsGuildLeader()`: se il personaggio non è più GM, la modifica viene annullata con un avviso.

## 2. Editor (bozzetti [`03-listing-editor.webp`](mockups/img/03-listing-editor.webp) e [`07-emblem-designer.webp`](mockups/img/07-emblem-designer.webp))

Una pagina con un **indice delle sezioni a sinistra**, che si possono saltare, e l'**anteprima dal vivo** a destra: la riga della lista come la vedranno gli altri.

| # | Sezione | Campi |
|---|---|---|
| 1 | **Identity** | nome della gilda (sola lettura, letto dal gioco, con l'icona di un lucchetto e il tooltip "Taken from your guild. Rename the guild in game to change it"); sottotitolo (contatore 0/60); stemma ([SPEC-08 §2](SPEC-08-assets-emblems-l10n.md#2-stemma)): "Use guild tabard" se c'è, altrimenti "Design emblem"; sfondo (galleria di miniature) |
| 2 | **About** | descrizione (casella su più righe, contatore 0/500); lingua principale (menu); lingue secondarie (scelta multipla) |
| 3 | **Activity** | **impegno** (segmented button Casual / Softcore / Hardcore, obbligatorio, con la spiegazione sotto); **tipi di attività** (etichette, **al massimo 3**: arrivati a 3 le altre si disattivano con il messaggio "Up to 3 activities: remove one to pick another"; l'ordine di scelta è l'ordine di importanza, con il numero 1-2-3 sull'etichetta); giorni (7 caselle); fascia oraria **nell'ora locale del GM** (menu ogni 30 min, "All day"), convertita e salvata in UTC |
| 4 | **Recruitment** | stato (Open / Selected classes only / Closed); **griglia "Looking for"**: una riga per classe e le colonne Tank, Healer, Melee, Ranged (le combinazioni non possibili sono disattivate), più la riga "Any class"; "New player friendly"; "Accept applications through the addon" (D7) |
| 5 | **Requirements** | livello minimo (cursore); livello minimo dell'equipaggiamento (facoltativo, con una casella per attivarlo, D11); nota (0/120) |
| 6 | **Contact** | Discord: il prefisso fisso `https://discord.gg/` seguito da una casella **per il solo codice**; incollando un link intero ne viene estratto il codice (D13). Personaggi da contattare: fino a 3, scelti con il completamento automatico dal roster |
| 7 | **Publish** | elenco di controllo e pulsante principale |

### Elenco di controllo (preso da Albion, migliorato)

Prima di Publish, ogni voce mostra ✓ o ✗ e porta alla sezione con il problema:

- ✓ You are the Guild Master
- ✓/✗ Subtitle (required)
- ✓/✗ Description: at least 30 characters
- ✓/✗ Main language
- ✓/✗ Commitment (Casual / Softcore / Hardcore)
- ✓/✗ 1 to 3 activities
- ✓/✗ Emblem (tabard or designed)
- ✓/✗ "Looking for" set, or recruitment closed
- ✓/✗ Discord code valid (only if filled in)

**Publish** è attivo solo quando tutte le voci obbligatorie sono ✓. Nella modifica di un annuncio esistente il pulsante diventa **Save changes**, ed è attivo solo se qualcosa è cambiato.

### Bozza

L'editor salva da solo una **bozza** (`ownListing.draft`) a ogni modifica: chiudere la finestra non fa perdere niente. "Discard changes" riporta all'ultima versione pubblicata.

Come lo fanno `UI/Editor.lua` e `UI/EditorModel.lua` (M3.2):

- L'editor è la scheda **Create Listing** del GM senza annuncio e, per modificare un annuncio già in lista, la pagina `ListingEditor` che M3.8 apre sopra My Guild. Pagina sinistra: i sette passi con il loro stato (✓ verde, ✗ rosso, "optional"), "n / 7 ready", la riga della bozza, il pulsante principale (**Publish listing**, o **Save changes** per un annuncio già in lista) con il motivo scritto sotto quando è spento, **Discard changes** e **Delist**. Barra del titolo: "Step n of 7", **Back** e **Next**. Contenuto: la pagina del passo a sinistra e, a destra, l'anteprima dal vivo (nome dal gioco, sottotitolo, lingue, impegno, attività), l'elenco di controllo e il nome della gilda (sola lettura). Il settimo passo mostra la scheda intera, disegnata dal disegnatore delle schede della lista (`Browse.CreateCard`), e l'elenco su tutta la larghezza.
- Le regole sono Lua puro in `UI/EditorModel.lua`, provate senza finestre. Ogni voce dell'elenco è `ok`, `todo` (obbligatoria e vuota), `bad` (presente ma non valida) oppure `optional` (niente da controllare: il codice Discord vuoto). Il testo della descrizione si conta in caratteri UTF-8 dopo la pulizia di SPEC-03 §6; "1 to 3 activities" rifiuta una quarta attività invece di tagliarla in silenzio; "Looking for" è soddisfatto da almeno una classe con almeno un ruolo, oppure da `rec = 0` (Closed). Ogni voce ha il passo che la sistema: un clic sulla voce porta lì.
- Il pulsante principale è spento, in quest'ordine, per: personaggio che non può modificare (non è GM, nessuna gilda, dati in sola lettura: la frase è quella di `OwnListing:Explain`); una voce non verde ("Fix "<passo>" to publish"; premuto da spento porta al passo); nessuna modifica (solo **Save changes**: l'annuncio uscito e la bozza producono lo stesso record, un link Discord e il suo codice contano come uguali); i 5 minuti non ancora passati (il conto alla rovescia scorre mentre la pagina è aperta). Un annuncio ritirato si ripubblica con un clic anche senza modifiche.
- La bozza si salva a ogni modifica con `OwnListing:SaveDraft`; la pagina conserva quello che è stato digitato (un link Discord resta un link finché non si pubblica). **Discard changes** e **Delist** chiedono conferma sul posto. Chi non è il GM e arriva alla pagina la vede coperta da una nota, e `OwnListing` rifiuta comunque ogni salvataggio.
- I passi 1-6 sono collegabili: `Editor.RegisterStep(id, { Build, OnShow, OnHide, Refresh })` e `Editor:Get/Set/Patch` (M3.3 Identity e About, M3.4 Activity, M3.5 Recruitment, Requirements e Contact); finché un passo non si registra, la sua pagina dice che arriva in una versione successiva. Senza i passi 3.3-3.6 il pulsante non può diventare verde nel client vero (l'emblema arriva con M3.6): nelle versioni di sviluppo il pulsante "Fill with sample values" dell'ultimo passo e `/gf debug publish` fanno da sostituti.

## 3. Pubblicazione e modifica

1. Il GM preme Publish o Save changes.
2. `rev = rev + 1`, `upd = GetServerTime()`; alla prima pubblicazione si generano anche `first` e `own`.
3. Viene inviato un `GLIST` in `GUILD`: tutti i membri online con l'addon aggiornano la loro copia.
4. Viene inviato un `ANN` nel canale pubblico; i membri lo ripetono con la soppressione ([SPEC-02 §5](SPEC-02-network-protocol.md#5-annunci-periodici-ann)).
5. Messaggio di conferma: "Listing published. It will reach other players over the next minutes."

Limite: al massimo 1 salvataggio pubblicato ogni 5 minuti, per contenere il traffico. Le bozze non hanno limiti.

Come lo fa `Data/OwnListing.lua` (M3.1, [ADR 0021](../adr/0021-guild-copy-of-the-listing-from-the-guild-master-only.md)):

- `rev` è la più alta conosciuta per la gilda (copia della gilda, riassunto pubblico, ritiro pubblico) più uno; `first` e `own` vengono dalla copia della gilda, altrimenti dal catalogo pubblico, altrimenti si creano.
- Il limite dei 5 minuti conta dall'ultima pubblicazione ed è salvato per personaggio (`ownListing.pubAt`): un `/reload` non lo azzera. Il ritiro non ha limiti.
- Dopo la pubblicazione la bozza viene cancellata: la versione pubblicata è il nuovo punto di partenza. Le statistiche (`st`, `srev`) arrivano con M3.7.

## 4. Ritiro (Delist)

- Pulsante secondario **Delist** con conferma: "Remove your guild from Guild Finder? Pending applications will be closed."
- Effetti: `GLIST` con lo stato delisted, `DEL` nel canale, candidature in attesa → declined, con il motivo "Listing removed".
- Il GM torna a vedere solo l'editor, precompilato con l'ultimo annuncio, per ripubblicare con un clic.
- Il ritiro è una revisione: `rev + 1` con `del = true` (il contenuto resta) nel `GLIST`, e `DEL {k, rev + 1}` nel canale; la nuova pubblicazione prende `rev + 2` e rimette l'annuncio in lista ovunque (INT-05). Le candidature in attesa → declined arrivano con M4.

## 5. Cambio di GM

- Il nuovo GM vede "My Guild" con l'annuncio esistente (ricevuto via `GLIST`) e può modificarlo: l'`ownerId` resta lo stesso perché è già nella copia della gilda.
- Il vecchio GM, se resta in gilda, perde l'editor al successivo `GUILD_RANKS_UPDATE`.
- I membri seguono il roster: appena il roster indica il nuovo GM, un `GLIST` del vecchio viene rifiutato. Se al nuovo GM non è mai arrivato un `GLIST`, la sua prima pubblicazione parte dal catalogo pubblico, con lo stesso `ownerId` (INT-03); se non c'è nemmeno quello, l'annuncio riparte da capo.
