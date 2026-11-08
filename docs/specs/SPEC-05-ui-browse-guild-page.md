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
