# Azeroth Guild Finder: specifiche di progetto

Addon **non ufficiale** per **WoW: Forever** che aiuta chi non ha gilda a trovarne una e aiuta GM e ufficiali a pubblicare l'annuncio della propria gilda e a gestire le candidature.

- Stato: **Bozza 1, da revisionare** (2026-11-08)
- Client di riferimento: WoW Forever `1.60.1.70862`, `## Interface: 16001`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`
- Distribuzione: CurseForge e GitHub Releases, installazione manuale
- Lingua dell'addon (V1): inglese, con localizzazione predisposta
- Lingua di questi documenti: italiano; nomi di codice, API e testi dell'interfaccia in inglese

## Indice

| # | Documento | Contenuto |
|---|---|---|
| 00 | [Visione, ambito e ruoli](SPEC-00-vision-scope.md) | obiettivi, V1/V2, ruoli e pannelli visibili, registro delle decisioni |
| 01 | [Piattaforma e architettura](SPEC-01-platform-architecture.md) | vincoli del client, architettura P2P, moduli, librerie, SavedVariables |
| 02 | [Protocollo di rete](SPEC-02-network-protocol.md) | canale, messaggi, sincronizzazione, limiti di traffico, integrità |
| 03 | [Modello dati](SPEC-03-data-model.md) | annuncio, statistiche, candidature, validazioni, normalizzazione dei nomi |
| 04 | [Struttura dell'interfaccia e design system](SPEC-04-ui-shell-navigation.md) | finestra a libro, barra laterale per ruolo, minimappa, `/gf`, tasto rapido, design system (Albion + Material 3, Roboto) |
| 05 | [Trova gilda e pagina della gilda](SPEC-05-ui-browse-guild-page.md) | lista, ricerca, filtri, pagina descrittiva |
| 06 | [Editor dell'annuncio (GM)](SPEC-06-ui-listing-editor.md) | creazione, modifica, anteprima, pubblicazione, ritiro |
| 07 | [Candidature](SPEC-07-applications.md) | flusso, stati, pannello GM/ufficiali, icona di notifica |
| 08 | [Grafica, stemmi e localizzazione](SPEC-08-assets-emblems-l10n.md) | stemma del tabarro, stemma alternativo, sfondi, traduzioni |
| 09 | [Qualità, spike e rilascio](SPEC-09-quality-release.md) | verifiche nel client, test offline, pacchetti, tappe |
| 10 | [Rischi e domande aperte](SPEC-10-risks-open-questions.md) | rischi tecnici e punti ancora da decidere |

Bozzetti delle schermate (v2): sorgenti HTML/CSS in [`mockups/html/`](mockups/html/), immagini WebP in [`mockups/img/`](mockups/img/) (con le note) e [`mockups/img/clean/`](mockups/img/clean/) (senza note). Si rigenerano con `bash docs/specs/mockups/render.sh` (Chrome headless + Pillow per la conversione in WebP). I testi dell'interfaccia sono in inglese, come nella V1.

| Bozzetto | Schermata |
|---|---|
| [00-design-system](mockups/img/clean/00-design-system.webp) | Design system: colori, Roboto / Roboto Mono, componenti, stemmi |
| [01-browse](mockups/img/01-browse.webp) | Trova gilda: lista, ricerca e filtri |
| [02-guild-page](mockups/img/02-guild-page.webp) | Pagina della gilda (visitatore) |
| [03-listing-editor](mockups/img/03-listing-editor.webp) | Editor dell'annuncio (GM), passo Recruitment |
| [04-applications](mockups/img/04-applications.webp) | Candidature (GM/ufficiali) |
| [05-notification](mockups/img/05-notification.webp) | Icona di notifica e lista rapida |
| [06-states](mockups/img/clean/06-states.webp) | Stati per ruolo: membro, nessun annuncio, GM, candidato |
| [07-emblem-designer](mockups/img/07-emblem-designer.webp) | Editor dello stemma (passo Identity) |
| [08-editor-activity](mockups/img/08-editor-activity.webp) | Editor dell'annuncio, passo Activity: impegno e massimo 3 attività |

Le **icone delle classi** nei bozzetti sono quelle del gioco, caricate dal CDN di Wowhead solo durante l'esportazione: nel repository non c'è nessun file di icone. Le icone dell'interfaccia (Material Symbols) e le illustrazioni sono invece **segnaposti**: nell'addon saranno icone e immagini del client.

## Convenzioni

- **MUST / SHOULD / MAY**: obbligatorio / raccomandato / facoltativo.
- Le API marcate **[verificare]** non compaiono nel dump `APIDocumentation` (sono globali storici o FrameXML) oppure il loro comportamento su Forever non è ancora stato osservato: vanno confermate nello spike ([SPEC-09](SPEC-09-quality-release.md#1-spike-tecnico-m0)).
- Ogni requisito ha un identificativo (`BR-xx`, `NET-xx`, `APP-xx`…) da citare nelle issue e nelle PR.
- Le decisioni che diventano definitive si registrano come ADR in `docs/adr/` (stesso formato di azeroth-unspoken).
