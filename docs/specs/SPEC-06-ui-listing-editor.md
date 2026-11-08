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

## 3. Pubblicazione e modifica

1. Il GM preme Publish o Save changes.
2. `rev = rev + 1`, `upd = GetServerTime()`; alla prima pubblicazione si generano anche `first` e `own`.
3. Viene inviato un `GLIST` in `GUILD`: tutti i membri online con l'addon aggiornano la loro copia.
4. Viene inviato un `ANN` nel canale pubblico; i membri lo ripetono con la soppressione ([SPEC-02 §5](SPEC-02-network-protocol.md#5-annunci-periodici-ann)).
5. Messaggio di conferma: "Listing published. It will reach other players over the next minutes."

Limite: al massimo 1 salvataggio pubblicato ogni 5 minuti, per contenere il traffico. Le bozze non hanno limiti.

## 4. Ritiro (Delist)

- Pulsante secondario **Delist** con conferma: "Remove your guild from Guild Finder? Pending applications will be closed."
- Effetti: `GLIST` con lo stato delisted, `DEL` nel canale, candidature in attesa → declined, con il motivo "Listing removed".
- Il GM torna a vedere solo l'editor, precompilato con l'ultimo annuncio, per ripubblicare con un clic.

## 5. Cambio di GM

- Il nuovo GM vede "My Guild" con l'annuncio esistente (ricevuto via `GLIST`) e può modificarlo: l'`ownerId` resta lo stesso perché è già nella copia della gilda.
- Il vecchio GM, se resta in gilda, perde l'editor al successivo `GUILD_RANKS_UPDATE`.
