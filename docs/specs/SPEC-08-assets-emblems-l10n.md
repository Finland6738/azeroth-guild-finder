# SPEC-08: Grafica, stemmi e localizzazione

## 1. Principio

Usiamo la grafica **già presente nel client**, citandola per percorso o fileID, senza estrarre né ridistribuire file di Blizzard (D9, D10). Nella cartella `Media/` dell'addon vanno solo elementi grafici nostri (maschere, cornici semplici). Ogni risorsa del client usata va in un **registro** (`Data/Assets.lua`) con percorso, fileID e data della verifica in gioco.

## 2. Stemma

**Un solo motore per due fonti.** Lo stemma è sempre composto con i **pezzi del tabarro di WoW**: sfondo, bordo ed emblema, ciascuno con il suo colore. Se la gilda ha un tabarro lo si copia così com'è; se non ce l'ha, il GM compone uno stemma con gli stessi pezzi, in un editor in stile Albion. Così le gilde con e senza tabarro hanno stemmi coerenti tra loro.

### 2.1 Da dove vengono i pezzi: niente da copiare

Le texture del tabarro sono **già installate nel client di ogni giocatore**, negli archivi CASC in `World of Warcraft\Data`, e un addon le usa indicando il loro **fileID**. Non serve, né si deve, copiarle nell'addon:

- **Copiare i file di Blizzard** dentro un addon distribuito su CurseForge o GitHub vorrebbe dire ridistribuire materiale protetto. Inoltre è inutile, perché ogni client li ha già.
- **Copiare la grafica di Albion Online** non è possibile: appartiene a un altro editore (Sandbox Interactive) ed è chiusa negli archivi di Unity. Da Albion prendiamo **l'idea** dell'editor (motivo, colori, simbolo, casuale), non i file.

API presenti nel dump di Forever:

| API | Uso |
|---|---|
| `C_GuildInfo.GetGuildTabardInfo("player")` | stemma attuale della gilda, con i fileID e i colori; i campi esatti vanno confermati nello spike (S8) |
| Widget `TabardModel`: `GetUpperEmblemFile()`, `GetUpperBorderFile()`, `GetUpperBackgroundFileName()` (e le versioni `Lower`) | fileID delle texture del tabarro mostrato |
| `TabardModelBase:CycleVariation(variation, delta)` | scorre le varianti (emblema, colore dell'emblema, bordo, colore del bordo, sfondo) come nel negozio dei tabarri di Blizzard |
| `TabardModelBase:InitializeTabardColors()`, `IsGuildTabard()` | inizializza il modello dai colori della gilda |

**Catalogo dei pezzi.** Durante lo spike, `/gf debug tabard` crea un `TabardModel` nascosto, lo fa scorrere con `CycleVariation` su tutte le varianti e annota i fileID di emblemi, bordi e sfondi e i colori disponibili. Il risultato diventa `Data/TabardParts.lua`: tabelle di **numeri**, cioè fileID e RGB, senza nessun file grafico. `Save()` non viene **mai** chiamato: l'addon non modifica il tabarro vero e non spende oro.

### 2.2 Stemma dal tabarro (preferito)

- Al momento della pubblicazione, se la gilda ha un tabarro, l'editor propone "Use guild tabard" (attivo di base) e legge `GetGuildTabardInfo("player")`.
- Nell'annuncio: `emb = { t = 1, e = emblemFileID, b = borderFileID, g = backgroundFileID, ec = rgb, bc = rgb, gc = rgb }`, con i colori come interi RGB a 24 bit.
- Si aggiorna con `GUILDTABARD_UPDATE`: l'editor propone "Your tabard changed: update the emblem?".

### 2.3 Stemma composto (alternativo, in stile Albion)

Per le gilde senza tabarro, o se il GM preferisce un altro stemma, c'è un editor con un'anteprima grande (bozzetto [`07-emblem-designer.webp`](mockups/img/07-emblem-designer.webp)):

| Sezione (come in Albion) | Pezzi di WoW usati | Scelta |
|---|---|---|
| Background | colori di sfondo del tabarro | tavolozza del catalogo |
| Border | bordi del tabarro | stile (frecce ◀ ▶) + colore |
| Emblem | emblemi del tabarro (griglia) | emblema + colore |
| Random / Reset | | combinazione casuale, ritorno al tabarro o a quella pubblicata |

Formato: lo stesso del §2.2 con `t = 2`, quindi chi lo riceve non deve distinguere i due casi.

### 2.4 Rendering e ripieghi

- Lo stemma si compone a strati in una cornice a forma di scudo, una maschera **nostra** in `Media/`: sfondo colorato (`SetVertexColor`), bordo, emblema e infine una cornice metallica nostra in stile Albion. Stesso componente a 48, 64 e 96 px.
- Un fileID che il client del destinatario non carica viene saltato. Se mancano tutti i pezzi, si mostra uno scudo neutro con l'iniziale della gilda.
- Lo stemma composto **non** diventa il tabarro della gilda in gioco: vale solo nel Guild Finder.

## 3. Sfondi

- Una galleria di **12–16 immagini** scelte tra le illustrazioni del client: schermate di caricamento delle zone, sfondi delle finestre degli achievement e della gilda.
- **Prima della V1** ogni immagine candidata passa la verifica in gioco con `/gf debug textures`:
  1. `Texture:SetTexture(fileID)` riesce e `GetTexture()` restituisce un valore;
  2. l'immagine compare in una finestra di prova alle dimensioni dell'intestazione (860 × 140, ritagliata con `SetTexCoord`);
  3. resta leggibile sotto il testo scuro, con una sfumatura pergamena dal 40 % in giù.
- Solo le immagini che superano la verifica entrano nel registro, con un **indice stabile**. Nell'annuncio viaggia l'indice (`bg`), non il fileID: gli indici non si riusano e un indice sconosciuto mostra lo sfondo predefinito.
- La pergamena della finestra principale va verificata allo stesso modo.

## 4. Icone

- **Classi**: sempre le **icone delle classi del gioco**, mai sigle o colori soli: le texture `Interface\Icons\ClassIcon_<Class>` (fileID nel registro) o l'atlante `classicon-<class>` [verificare quale delle due c'è su Forever]. Intorno all'icona un anello sottile nel colore della classe (`RAID_CLASS_COLORS`), come nei bozzetti. Tre misure: 20 px (righe e anteprime), 26 px (tabelle), 40 px ("Looking for").
- **Ruoli**: quattro badge rotondi con colore e simbolo distinti, sempre con il nome nel tooltip: **Tank** blu (scudo), **Healer** verde (croce), **Melee DPS** rosso (spade incrociate), **Ranged DPS** viola (bersaglio). L'icona dei ruoli del cercagruppi di Blizzard ha solo Tank/Healer/DPS, quindi i badge sono texture **nostre** in `Media/` (64 px, ridotte a 14–28 px). Il bersaglio vale sia per le classi con l'arco sia per gli incantatori.
- **Tipi di contenuto**: un'icona del gioco per ciascuno (esempio: Raids → icona di un boss, Battlegrounds → bandiera), da scegliere e registrare nello spike.
- **Lingue**: etichette di testo (`EN`, `IT`, `DE`…), non bandiere: più leggibili e senza problemi politici.

## 5. Localizzazione (D22)

- AceLocale-3.0, con l'inglese (`enUS`) come lingua base e completa. Ogni testo dell'interfaccia passa da `L["KEY"]` e nessuna stringa visibile è scritta direttamente nel codice.
- Chiavi in inglese e descrittive (`L["APPLY_BUTTON"]`, `L["REQ_NOT_MET_LEVEL"]` con `%d`).
- Date e ore con formati che non dipendono dalla lingua nella V1 (`12 Oct 2026`, `20:00`), centralizzati in `Core/Format.lua`.
- Pronto per `itIT` nella V2: si aggiunge un file `Locale/itIT.lua` e lo si dichiara nel TOC, senza toccare il codice.
- I contenuti scritti dai GM (sottotitolo, descrizione) **non** si traducono: si mostrano come sono, con la loro lingua dichiarata.
