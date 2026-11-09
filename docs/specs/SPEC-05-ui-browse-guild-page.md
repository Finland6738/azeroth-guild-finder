# SPEC-05: Trova gilda e pagina della gilda

Visibile solo a chi **non ha gilda** ([SPEC-00 §5](SPEC-00-vision-scope.md#5-ruoli-e-pannelli-visibili)). La pagina della gilda (§3) si riusa anche per "My Guild" ([SPEC-06](SPEC-06-ui-listing-editor.md)).

## 1. Lista (bozzetto [`01-browse.webp`](mockups/img/01-browse.webp))

### Barra superiore

- Casella di ricerca "Search guild name…": filtra mentre si scrive (con 250 ms di attesa), da 3 lettere normalizzate in su ([SPEC-03 §7](SPEC-03-data-model.md#7-normalizzazione-dei-nomi-ordinamento-e-ricerca-d19)). Con meno di 3 lettere compare il suggerimento "Type at least 3 letters".
- A destra il numero dei risultati ("24 of 142 guilds") e l'indicazione fissa "Sorted A → Z". **Non c'è un menu di ordinamento** (D19).

### Riga di una gilda (scheda in stile Albion, circa 176 px)

| Zona | Contenuto |
|---|---|
| Riquadro, a sinistra | stemma 84 px con la cornice metallica ([SPEC-08 §2](SPEC-08-assets-emblems-l10n.md#2-stemma)) |
| Riquadro, al centro | **nome** (19 px, grassetto), sottotitolo (al massimo 2 righe, "…"), etichette delle lingue (`IT` `EN`), "✓ Looking for your class" o "✗ Requirements not met" |
| Riquadro, a destra | **illustrazione** scelta dal GM, sfumata nella pergamena da sinistra a destra; sopra, i pulsanti **Discord** (blu) e **Apply** (rosso, o grigio se non disponibile) |
| Fascia di informazioni (2 righe × 3 colonne) | membri attivi ("31 active / 149"); giorni e orari locali (in Roboto Mono); **classi cercate** (al massimo 4, poi "+1"); tipi di attività (al massimo 3) e impegno; requisito principale con ✓/✗; "Updated 2 days ago" |

- Clic sulla riga (fuori dai pulsanti): apre la pagina della gilda (§3). **Discord** apre un piccolo riquadro con il link già selezionato da copiare; **Apply** chiede conferma ([§4](#4-pulsante-apply-stati)).
- Passando sopra la riga: un tooltip con la descrizione abbreviata e i requisiti.
- Un annuncio senza `ANN` da più di 14 giorni mostra "May be inactive"; dopo 30 giorni sparisce dalla lista (resta in cache fino a 60).

> **Nota di realizzazione (M2.5).** Roboto non contiene le frecce né il segno di spunta: l'addon scrive "Sorted A-Z" (con il trattino) e usa piccole icone per i segni ✓/✗ dei requisiti. Il tag in alto sulla scheda è uno solo: "Requirements not met" se un requisito noto non è soddisfatto, altrimenti "Looking for your class". I pulsanti **Discord** e **Apply** della scheda arrivano con la pagina della gilda (M2.7) e le candidature (M4). Giorni e orari sono convertiti dal fuso UTC a quello del computer del giocatore (`BrowseModel.ToLocal`); un banner di cui non è ancora noto il fileID non viene disegnato.

### Stati della lista

| Stato | Messaggio |
|---|---|
| Catalogo vuoto, sincronizzazione in corso | rotellina + "Looking for guilds… this can take a minute the first time" |
| Nessun peer online | "No other Guild Finder users online right now. Listings will appear as they come online." |
| Filtri senza risultati | "No guild matches your filters" e il pulsante "Reset filters" |

## 2. Filtri (pagina sinistra del libro)

| Filtro | Tipo | Regola |
|---|---|---|
| Recruiting only | interruttore (attivo di base) | `rec ≠ 0` |
| Looking for my class | interruttore | `want[myClass]` o `want[0]` |
| Role | Tank / Healer / Melee / Ranged, scelta multipla (etichette con l'icona del ruolo) | almeno un ruolo cercato in comune, per la mia classe o per qualsiasi classe |
| Requirements met | interruttore | livello ed equipaggiamento soddisfatti |
| New player friendly | interruttore | `newb` |
| Language | menu a scelta multipla | almeno una lingua in comune |
| Commitment | Casual / Softcore / Hardcore, scelta multipla | `pace` tra quelli scelti |
| Activity | etichette a scelta multipla (tutte e 13) | almeno un'attività in comune con i `tags` della gilda |
| Play days | 7 caselle | almeno un giorno in comune |
| Play time (local) | da – a | la fascia si sovrappone, anche a cavallo della mezzanotte |
| Active members | minimo (0, 5, 10, 25, 50) | `a7 ≥ valore` |
| Reset all filters | pulsante | |

I filtri si ricordano per personaggio. Il numero di filtri attivi compare nella targhetta in cima ("Filters · 4 active"), con il pulsante per azzerarli.

> **Nota di realizzazione (M2.6).** Le regole stanno in `UI/FilterModel.lua` (puro Lua, provato senza interfaccia); `UI/FilterPanel.lua` disegna solo i controlli. Dettagli che la tabella non dice:
>
> - Un personaggio che non ha mai scelto ha **solo "Recruiting only"** attivo. **Reset** (il pulsante rotondo sulla targhetta e quello dello stato "nessun risultato") spegne **tutti** i filtri, anche "Recruiting only": la lista torna completa. Il contatore conta un filtro per voce, qualunque sia il numero di scelte.
> - **Role**: i ruoli che la classe del giocatore non può svolgere (SPEC-03 §5) sono attenuati con la ragione nel tooltip e sono scartati se arrivano dai dati salvati. Il ruolo scelto va confrontato con quelli cercati per la **mia classe** e per **qualsiasi classe** (`want[0]`).
> - **Language**: conta anche `lang1`. **Activity** è un menu a scelta multipla (come nel bozzetto) e non tredici etichette, per stare nei 260 px della pagina sinistra.
> - **Requirements met**: scarta solo ciò che si sa non soddisfatto (livello o livello medio dell'equipaggiamento noti e troppo bassi); un dato che il client non dà non esclude.
> - **Play days** e **Play time** si confrontano **nel fuso del computer**: giorni e orari UTC dell'annuncio vengono convertiti con `BrowseModel.ToLocal` (i giorni scorrono insieme all'ora d'inizio). La fascia filtro `da-a` si sovrappone se hanno almeno un minuto in comune; due fasce che si toccano soltanto non si sovrappongono; `da > a` attraversa la mezzanotte; solo `da` va fino a mezzanotte, solo `a` parte da mezzanotte; `da == a` significa tutto il giorno e non filtra; un annuncio con `t0 == t1` ("All day") combacia con ogni fascia. Giorni e fascia sono due condizioni separate, non una coppia giorno-ora.
> - Un annuncio che non dichiara ciò che il filtro chiede (nessun giorno, nessun orario, nessuna statistica, nessuna lingua, nessuna attività) **non** passa mentre quel filtro è acceso.
> - Lo stato è salvato in `char.ui.filters` ad ogni modifica come numeri e booleani (maschere: ruoli 0–15, lingue bit *i*−1, impegni bit *pace*−1, attività bit *id*−1, giorni lunedì = bit 0) e viene riparato quando è danneggiato. Ogni modifica riporta la lista in cima.

## 3. Pagina della gilda (bozzetto [`02-guild-page.webp`](mockups/img/02-guild-page.webp))

La pagina **sostituisce** la lista e usa le due pagine del libro.

**Pagina sinistra: chi sono e cosa posso fare**

1. "← Back to results" (filtri e posizione nella lista vengono conservati).
2. Stemma grande (150 px), nome, sottotitolo, lingue, fazione e **impegno** (Casual / Softcore / Hardcore).
3. Pulsante principale **Apply to <Guild>** con il suo stato ([§4](#4-pulsante-apply-stati)) e una riga di spiegazione.
4. **Contact**:
   - Discord: campo di sola lettura in Roboto Mono con `https://discord.gg/<code>`. **Al clic seleziona tutto il testo** e mostra "Press Ctrl+C to copy" (D13). In WoW i link esterni non si aprono.
   - Personaggi da contattare: nome, pallino verde se si sa che è online (da `ANN` recenti), pulsante **Whisper** che apre `/w Nome `.
5. In fondo: "Listed since 12 Oct 2026 · Updated 2 days ago".

**Pagina destra: i dettagli**

1. **Illustrazione** scelta dal GM (150 px), sfumata in basso.
2. **"Looking for"**: card con il bordo oro sovrapposta all'illustrazione, sempre in cima (D11).
   - Classi in grande (40 px), ciascuna con le icone dei ruoli cercati.
   - "Any class: Healer" se `want[0]`.
   - Stato: "Recruiting" (verde) / "Recruiting: selected classes only" (oro) / "Recruiting closed" (rosso).
   - Se la classe e il ruolo del visitatore sono cercati: "✓ They need your class: Mage · Ranged DPS". Sotto le classi, una legenda delle quattro icone dei ruoli.
3. Due colonne di card:
   - **About** (descrizione completa) e **Activity** (l'**impegno** come etichetta colorata con la spiegazione nel tooltip; le attività, fino a 3, come etichette numerate per importanza; i giorni in 7 caselle; la fascia oraria **nel fuso del visitatore** in Roboto Mono, con UTC più in piccolo; "All day" se `t0 == t1`);
   - **Members** ("Active characters · 7 days", "Unique players · 7 days" come intervallo con tooltip, "Total members", "At max level", barra della distribuzione delle classi, "updated 3 h ago") e **Requirements** (ogni requisito con ✓ o ✗ calcolato per il visitatore, più la nota del GM).
4. **How applying works**: tre passi spiegati in una riga, per chi non ha mai usato l'addon.

Il dettaglio può non essere ancora disponibile (solo il riassunto in cache). In quel caso About e Contact mostrano "Loading details…" mentre parte `DETREQ`. Dopo 20 s senza risposta: "Details unavailable right now (no one who has them is online)". Le altre sezioni si vedono comunque.

> **Nota di realizzazione (M2.7).** Le regole stanno in `UI/GuildPageModel.lua` (puro Lua, provato senza interfaccia); `UI/GuildPage.lua` disegna soltanto. La pagina è registrata come `GuildPage` e `Browse:OpenGuild(k)` la mette sopra la scheda *Find a Guild* con `{ k = guildKey }`; il pulsante **Back** del titolo (e Backspace) è quello della finestra, non uno della pagina sinistra. Dettagli che il testo non dice:
>
> - **Riassunto e dettaglio**: la pagina si disegna con il solo riassunto (la lista lo ha già) e si completa quando arriva il dettaglio. Descrizione, codice Discord, contatti e nota richiedono il dettaglio; finché manca dicono "Loading details..." e all'apertura parte `Sync:RequestDetail(k)` (se il dettaglio manca o è più vecchio del riassunto). Dopo 20 s il Bus dà `DETAIL_UNAVAILABLE(k)` e compare "Details unavailable right now (no one who has them is online)": il segnale si ricorda in memoria e si azzera a ogni apertura, che chiede di nuovo. Un dettaglio che arriva dopo (`CATALOG_UPDATED k "detail"`) completa comunque la pagina aperta, subito; le statistiche e le modifiche ridisegnano dopo 0,3 s. Un dettaglio **più vecchio** del riassunto viene mostrato mentre si chiede quello nuovo. Un annuncio `localOnly` (il seme di sviluppo) non ha nessuno a cui chiedere: senza dettaglio è "unavailable" subito, e `/gf debug seed` dà un dettaglio finto a due annunci su tre.
> - **Un annuncio che sparisce** (ritirato, nascosto o rimosso) mentre la pagina è aperta: la pagina destra dice "This listing is no longer available. Go back to the list." e la sinistra tiene solo emblema e nome.
> - **Apply**: non c'è fino a M4. Con `apps = false` la pagina sinistra dice "Applications via addon are closed. Use the contacts below.".
> - **Contatti**: nome e pallino come da §3; il pallino è verde se `Sync:Contacts(k, 3600)` (gli `ANN` con `c=1` sentiti nell'ultima ora) contiene quel personaggio, confrontato senza reame e senza maiuscole; il ruolo (GM o ufficiale) non si sa, quindi non viene scritto. **Whisper** usa `Compat.Chat.OpenWhisper` (`ChatFrame_OpenChat("/w Nome ")`); se il client non lo permette, una snackbar dice cosa scrivere.
> - **"They need your class"** richiede un ruolo in comune: i ruoli voluti per la **mia classe** più quelli voluti per **qualsiasi classe**, ridotti ai ruoli che la classe può svolgere (SPEC-03 §5). Un Mage con "any class: Healer" **non** vede la riga, mentre l'etichetta "Looking for your class" della lista (`BrowseModel.WantsClass`) e il filtro "Looking for my class" guardano solo la classe; la differenza è voluta per ora e va decisa insieme al filtro dei ruoli.
> - **Requisiti**: stesso calcolo della lista (`BrowseModel.Requirements`), mostrato riga per riga: livello, livello dell'equipaggiamento ("No level requirement" e "No item level requirement" in grigio quando non richiesti), nota del GM tra virgolette. Un dato che il client non dà (livello medio) non mette né ✓ né ✗.
> - **Giorni e orari**: `BrowseModel.ToLocal` e `LocalOffset` (fuso del computer); la fascia UTC è mostrata in piccolo; "All day" senza "your time" e senza UTC.
> - **Membri**: l'intervallo dei giocatori unici ("19–24", o un numero se `lo == hi`), "updated" dall'ora `srev`, barra delle classi con i colori delle classi; senza statistiche una frase sola.
> - **Layout**: la pagina destra scorre con la rotella (anche sopra icone e etichette) e con la barra quando è più alta della finestra; le altezze delle card seguono i testi (`GetStringHeight`), le colonne, i gruppi di etichette e le liste di caselle si dispongono con `Model.Stack`, `Model.Flow` e `Model.Columns`. Il banner è una tavola marrone finché `Assets.BANNERS` è vuoto.

## 4. Pulsante Apply: stati

| Condizione | Pulsante | Testo |
|---|---|---|
| candidature aperte, requisiti ok, nessuna candidatura aperta | attivo | **Apply** |
| già candidato a questa gilda | disattivato | "Applied · Pending" (link alla scheda My Application) |
| candidatura aperta verso un'altra gilda | disattivato | "You already applied to <Guild>" (tooltip: "Withdraw it first") |
| requisiti non soddisfatti | disattivato | "Requirements not met" |
| candidature chiuse dal GM (`apps = false`) | nascosto | al suo posto: "Applications via addon are closed. Use the contacts below." |
| rifiuto negli ultimi 7 giorni | disattivato | "You can apply again on 15 Nov" |
| il client non può inviare (modo solo ascolto) | disattivato | "Your character can't send addon messages yet" |

Dopo il clic compare una conferma ("Apply to <Guild> with Name (Mage 32)?"), poi il testo diventa "Applied · Waiting for an officer" o "Applied · Received".
