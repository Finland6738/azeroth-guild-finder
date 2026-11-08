# SPEC-04: Struttura dell'interfaccia e navigazione

## 1. Cosa cambia rispetto ad Albion

| In Albion | Problema | Da noi |
|---|---|---|
| 3 schede con sole icone (stella, lente, lista) sul bordo destro | non si capisce cosa contengano; due su tre sono la stessa lista con filtri diversi | la stessa **barra metallica laterale**, ma ogni scheda ha **icona ed etichetta** (navigation rail di Material 3), e una sola vista di ricerca |
| Suggerimenti, ricerca per nome e filtri in tre viste separate | per cercare per nome *e* filtrare per lingua bisogna cambiare vista | ricerca per nome **sopra** la lista e filtri **a fianco**, nella stessa vista |
| Il dettaglio della gilda è una finestra sopra la lista, con altre 3 icone | finestre sovrapposte, sezioni nascoste | il dettaglio **sostituisce** la lista, con il pulsante "← Back" e le sezioni una sotto l'altra |
| Orari in UTC | bisogna fare il conto a mente | orari nel **fuso locale** di chi guarda, con i giorni |
| Classi cercate assenti | è l'informazione più cercata | riquadro **"Looking for"** in evidenza |
| Creazione con l'elenco dei requisiti mancanti ("Nome gilda non valido", "Stemma assente") | buona idea | **ripresa** nell'editor: un elenco di controllo prima di Publish |

## 2. Finestra principale

- Dimensioni: 1116 × 768 px a scala 100 %, scalabile (60–140 %), spostabile; posizione e scala salvate. Si chiude con `Esc` (registrata in `UISpecialFrames`) o con il pulsante rotondo dorato in alto a destra. Su uno schermo piccolo la scala usata viene ridotta perché il libro, la barra laterale e il pulsante di chiusura restino visibili; la scala scelta resta salvata (`Nav.FitScale`). La scala è salvata per tutto l'account, la posizione per personaggio, e la posizione si conserva sullo schermo quando la scala cambia.
- Struttura a **libro aperto**, come in Albion (bozzetti in [`mockups/img/`](mockups/img/)):

```
┌───────────────┬──────────────────────────────────────────┐(x)┌──────────┐
│ PAGINA SINISTRA│ PAGINA DESTRA                            │   │ ⚙ Settings│ ← sempre per prima
│ marchio /      │ intestazione (ricerca, titolo del passo)  │   ├──────────┤
│ stemma         │                                           │   │ ◉ Find a │ ← poi le schede del ruolo,
│ contesto:      │ contenuto (lista, pagina della gilda,     │   │   Guild  │   una sotto l'altra, senza spazi;
│ filtri, passi  │ editor, candidature)                      │   ├──────────┤   icona + etichetta, badge
│ dell'editor,   │                                           │   │ ◉ My     │
│ azioni         │ barra di stato: "142 guilds · synced…"    │   │   Applic.│
└───────────────┴──────────────────────────────────────────┘   └──────────┘
```

- **Pagina sinistra (312 px)**: il contesto della scheda. Filtri nella ricerca; stemma, azioni (Apply, Discord, Whisper) e contatti nella pagina della gilda; passi e Publish nell'editor; contatori e opzioni nelle candidature.
- **Pagina destra**: il contenuto principale.
- **Barra laterale**: fuori dal libro, a destra, come in Albion. Le voci sono **una sotto l'altra, senza spazi**: prima **Settings**, sempre presente e nella stessa posizione per tutti i ruoli, poi le schede del ruolo. La scheda attiva sporge e ha il bordo dorato.
- **Schede per ruolo**: la tabella di visibilità è in [SPEC-00 §5](SPEC-00-vision-scope.md#5-ruoli-e-pannelli-visibili). Anche quando è visibile una sola scheda (per esempio "Create Listing") resta mostrata come scheda, così si capisce sempre in quale sezione ci si trova.
- **Pagine dentro una scheda**: una piccola pila di navigazione. Il pulsante "← Back" e il tasto `Backspace` tornano indietro; filtri e posizione nella lista vengono ricordati.
- **Barra di stato**: numero di gilde conosciute, ora dell'ultima sincronizzazione e, se servono, gli avvisi ("Read-only: your character can't send addon messages yet", "Paused during combat").
- **[?]**: un breve aiuto contestuale, che sostituisce la colonna di spiegazioni di Albion.

## 3. Come si apre (D21)

| Modo | Dettagli |
|---|---|
| Pulsante sulla minimappa | LibDBIcon. Clic sinistro apre o chiude; clic destro apre le impostazioni; il tooltip mostra "3 pending applications" per GM e ufficiali |
| Addon Compartment | `## AddonCompartmentFunc` nel TOC (il client lo supporta) |
| Comando | `/gf`, con l'alias `/guildfinder` se `/gf` è già usato. Sottocomandi: `/gf notify` (icona di notifica), `/gf reset` (posizione della finestra), `/gf scale 60`–`140` (dimensione), `/gf debug` (diagnostica e verifica delle API; `/gf debug gallery`, solo nelle build di sviluppo, mostra un esemplare di ogni widget per la verifica in gioco), `/gf help` |
| Tasto rapido | `Bindings.xml`, voce "Toggle Guild Finder" in Tasti → AddOns. Nessun tasto assegnato di base |

## 4. Impostazioni

Pagina in `Settings` (`Settings.RegisterCanvasLayoutCategory`), con poche voci:

- Show minimap button
- Show applications notification icon (solo GM e ufficiali) e "only when pending"
- Play sound on new application
- Share anonymous alt count with my guild ([SPEC-03 §4](SPEC-03-data-model.md#4-statistiche))
- UI scale
- Reset window positions

## 5. Design system (D20): Albion fuori, Material dentro

Riferimento visivo: [`00-design-system.webp`](mockups/img/clean/00-design-system.webp); i token sono in [`mockups/html/agf.css`](mockups/html/agf.css).

### 5.1 Valutazione di Material Design

| Opzione | Giudizio |
|---|---|
| Material Design "puro" (superfici piatte, bianco e colori primari) | **No**: dentro WoW sembrerebbe un'app del telefono incollata sul gioco e stonerebbe con le altre finestre |
| Solo l'aspetto di Albion, senza regole | **No**: bello, ma con gli stessi difetti di Albion (icone senza etichetta, gerarchia poco chiara) |
| **Aspetto fantasy alla Albion sullo scheletro di Material 3** | **Sì**: pergamena, metallo, pulsanti lucidi e stemmi per l'atmosfera; da Material 3 la struttura, cioè la griglia di 8 px, la scala tipografica, i componenti (navigation rail con etichette, filled/tonal button a pillola, filter chip, switch, segmented button, card, snackbar, badge) e le regole di stato e accessibilità |

Corrispondenze principali: navigation rail → schede metalliche **con etichetta**; filled button → pillola rossa lucida; tonal button → pillola di pergamena; filter chip → etichetta di cuoio con il segno di spunta; outlined field → campo di pergamena in un anello d'acciaio; elevation → ombre marroni morbide.

### 5.2 Font

- **Roboto** per tutta l'interfaccia (Regular 400, Medium 500, Bold 700, Black 900 per il titolo della finestra).
- **Roboto Mono** solo dove serve allineare o distinguere caratteri: link e codici Discord, orari (`20:00–23:30`), comandi (`/gf notify`), diagnostica.
- Inclusi nell'addon in `Media/Fonts/` con la licenza **SIL Open Font License 1.1** (`OFL-Roboto.txt`, `OFL-RobotoMono.txt`: i font restano sotto la OFL, il resto dell'addon è GPL-3.0) e registrati come `FontObject` dell'addon (`CreateFont` + `SetFont`). Non si cambiano i font del resto del gioco. Se il client non riesce a caricare un file ([ADR 0020](../adr/0020-original-media-own-nine-slice-and-font-fallback.md)) quello stile usa il font del client con le stesse dimensioni; `/gf debug` elenca gli stili in ripiego.
- **Copertura dei caratteri**: Roboto copre latino, latino esteso, greco e cirillico. Per nomi con caratteri non coperti si ripiega sul font del client: `FontFamily` con i fallback per alfabeto [verificare].
- Scala tipografica (px a scala 100 %): headline 24/700 · title-l 20/700 · title-m 16/500 · body 13,5/400 · label 12,5/500 · caption 12/400 · mono 12–13. **Minimo 12 px.**

### 5.3 Colori, superfici e stato

- **Pergamena** (`parch` `#f6d6a6`, pagina sinistra più scura `#e9c897`) con grana leggera; **metallo** (acciaio `#9aa4ae`, ferro `#2a2e33`) per cornici, barra laterale e chiusura; **oro** `#f2bf3c` per la selezione e la scheda attiva.
- **Testo**: inchiostro `#3b2412` su pergamena, contrasto ≥ 7:1; testo secondario `#6a4526` ≥ 4,5:1. Niente testo chiaro su pergamena.
- **Azioni**: rosso lucido = azione principale (una sola per schermata), blu = solo Discord, pergamena = secondarie, grigio = disattivato **con il motivo scritto** accanto.
- **Stato**: verde `#2e7d32` (soddisfatto, ricevuto), rosso `#b3261e` (non soddisfatto, rifiutato), oro (nuovo, evidenza). Mai solo il colore: sempre anche un'icona o un testo.
- **Illustrazioni**: nelle righe della lista e nelle intestazioni, immagini del client sfumate nella pergamena a destra, come in Albion ([SPEC-08 §3](SPEC-08-assets-emblems-l10n.md#3-sfondi)).

### 5.4 Fattibilità in WoW

Tutto si costruisce con oggetti standard, senza librerie grafiche:

- pillole, campi e card: texture **nine-slice** nostre in `Media/` (angoli arrotondati, bordo metallico, lucido) + `SetVertexColor` per le varianti di colore;
- gradienti: `Texture:SetGradient`;
- ombre: texture sfumate nostre sotto le card e la finestra;
- grana della pergamena: una texture nostra ripetuta (tile), oppure la pergamena del client se la verifica dello spike la conferma;
- icone: icone del client per classi, ruoli e contenuti. Le Material Symbols dei bozzetti sono solo segnaposti.

### 5.5 Densità e accessibilità

- Righe della lista: circa 176 px (riquadro con illustrazione + fascia di informazioni, come Albion); il testo lungo viene tagliato con "…" e mostrato intero nel tooltip.
- Tutto si usa anche senza trascinare; tooltip su ogni icona; i colori delle classi sono sempre accompagnati da sigla o nome.
