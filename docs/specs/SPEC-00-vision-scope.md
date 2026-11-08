# SPEC-00: Visione, ambito e ruoli

## 1. Problema

Su WoW Forever non c'è un cercagilde. Chi gioca da solo trova le gilde solo leggendo la chat commerciale o i server Discord, mentre GM e ufficiali reclutano scrivendo nei canali pubblici. L'addon offre un **catalogo condiviso delle gilde**, consultabile in gioco, e un **flusso di candidatura con un clic**.

## 2. Obiettivi

1. Chi non ha gilda trova in meno di un minuto le gilde compatibili per lingua, contenuti, orari e classe cercata.
2. La pagina di una gilda mostra informazioni **oneste**: attività reale degli ultimi 7 giorni e solo dati aggregati.
3. Il GM pubblica e aggiorna l'annuncio senza uscire dal gioco; GM e ufficiali vedono e gestiscono le candidature.
4. L'interfaccia è più intuitiva di quella di Albion Online: schede con testo, una sola vista di ricerca, pagine invece di finestre sovrapposte.

## 3. Cosa resta fuori (sempre)

- Non sostituisce la creazione della gilda di Blizzard (carta e firme): pubblica solo annunci di **gilde già esistenti**.
- Nessun server esterno e nessun componente lato server: **solo l'addon**, che comunica in modalità peer-to-peer ([SPEC-01](SPEC-01-platform-architecture.md)).
- Nessuna moderazione centralizzata: niente segnalazioni, niente filtro delle parole, niente amministratori dell'addon (decisione D18).
- Nessuna classifica e nessun ordinamento a pagamento o per numero di ripubblicazioni: la lista è **sempre in ordine alfabetico** (D19).
- Nessun dato del singolo giocatore esposto: le statistiche sono solo aggregate (D12).

## 4. Ambito per versione

### V1 (prima versione pubblica)

| Area | Contenuto |
|---|---|
| Trova gilda | lista alfabetica, ricerca per nome, filtri (lingua, contenuti, giorni e orari, reclutamento, classe/ruolo cercati, requisiti, per nuovi giocatori, membri attivi) |
| Pagina della gilda | intestazione con stemma e sfondo, riquadro **"Cerchiamo"** in evidenza, descrizione, contenuti e orari, statistiche aggregate, requisiti con verifica, contatti (Discord da copiare, personaggi da contattare), pulsante Candidati |
| Annuncio (GM) | creazione, modifica, anteprima, pubblicazione, ritiro; nome preso in automatico dalla gilda in gioco |
| Candidature | candidatura con un clic (al massimo 1 aperta per personaggio), pannello per GM e ufficiali, icona di notifica mobile, invito in gilda |
| Navigazione | pulsante sulla minimappa (e nell'Addon Compartment), `/gf`, tasto rapido configurabile |
| Lingua | interfaccia in inglese, sistema di localizzazione pronto |

### V2 e successive (backlog)

- Gilde consigliate (lingua, attività, orari) come in "Suggerimenti" di Albion (D8).
- Statistiche avanzate: progressi nei raid, attività PvP (D12).
- Integrazione nelle finestre di Blizzard (Gilda o Social), se tecnicamente compatibile (D21).
- Traduzione italiana dell'interfaccia e altre lingue (D22).
- Firma crittografica degli annunci, se compaiono abusi ([SPEC-02 §8](SPEC-02-network-protocol.md#8-integrità-e-limiti-del-modello-p2p)).

## 5. Ruoli e pannelli visibili

Il ruolo si ricava **solo dal client**, nel momento in cui serve, e si aggiorna a ogni `PLAYER_GUILD_UPDATE`, `GUILD_ROSTER_UPDATE` e `GUILD_RANKS_UPDATE`.

| Ruolo | Come si riconosce | API |
|---|---|---|
| Senza gilda | non è in una gilda | `IsInGuild()` |
| Membro | in gilda, né GM né ufficiale | `IsInGuild()` |
| Ufficiale | ha il ruolo di ufficiale nei gradi della gilda | `C_GuildInfo.IsGuildOfficer()` |
| GM | è il capo effettivo della gilda | `IsGuildLeader()` |

Matrice di visibilità (richiesta esplicita, D-finale):

| Ruolo / stato dell'annuncio | Pannelli visibili |
|---|---|
| **Senza gilda** | **Find a Guild** (lista, filtri, pagina della gilda) e **My Application** |
| **Membro**, annuncio pubblicato | **My Guild**, la pagina della propria gilda in sola lettura |
| **Membro**, nessun annuncio | **My Guild**, con lo stato vuoto: "Your guild has no listing yet" |
| **GM**, nessun annuncio | solo **Create Listing**, l'editor |
| **GM**, annuncio pubblicato | **My Guild**, la pagina con i pulsanti Edit e Delist, e **Applications** |
| **Ufficiale**, annuncio pubblicato | **My Guild**, la pagina in sola lettura, e **Applications** |
| **Ufficiale**, nessun annuncio | **My Guild**, con lo stato vuoto: "Ask your Guild Master to publish a listing" |

Conseguenze:

- Chi è in gilda **non vede** la ricerca delle altre gilde.
- L'icona di notifica delle candidature esiste solo per il GM e per gli ufficiali.
- Quando cambia il ruolo con la finestra aperta, la finestra si ricostruisce e torna alla prima scheda valida.

## 6. Registro delle decisioni (risposte del 2026-11-08)

| ID | Decisione |
|---|---|
| D1 | Client: **WoW Forever** ufficiale, Interface 16001 (verificato nella cartella `_forever_`) |
| D2 | **Solo l'addon**, comunicazione P2P; nessun componente lato server |
| D3 | Distribuzione su CurseForge e GitHub, installazione manuale |
| D4 | Gilde divise per fazione: il catalogo è separato per reame e fazione |
| D5 | Un solo reame |
| D6 | Si pubblicano annunci di gilde esistenti; la creazione delle gilde resta quella di Blizzard |
| D7 | Il GM può aprire o chiudere le candidature; una candidatura aggiunge il personaggio a una lista visibile a GM e ufficiali |
| D8 | Gilde consigliate rimandate alla V2 |
| D9 | Stemma del tabarro; se manca, uno stemma alternativo composto con la grafica del gioco |
| D10 | Sfondi scelti tra immagini del client, dopo averne verificato l'uso dagli addon |
| D11 | Tutti i campi proposti; requisito di equipaggiamento facoltativo; **classi e ruoli cercati ben in evidenza** |
| D12 | Statistiche aggregate, con al centro l'attività reale degli ultimi 7 giorni; **personaggi attivi distinti dai giocatori unici**; data di fondazione solo se attendibile; raid e PvP in seguito |
| D13 | Discord: prefisso fisso `https://discord.gg/` più il codice d'invito; campo da selezionare per copiarlo |
| D14 | Solo il GM effettivo crea e modifica l'annuncio; gli ufficiali vedono le candidature |
| D15 | Candidatura con un pulsante, senza modulo |
| D16 | Al massimo **1 candidatura aperta** alla volta |
| D17 | Icona di notifica sullo schermo che si può mostrare o nascondere; al clic apre la lista delle candidature |
| D18 | Nessuna moderazione (segnalazioni, filtri, staff) |
| D19 | Ordine **sempre alfabetico crescente**, con la chiave normalizzata (senza accenti, simboli, numeri e spazi; maiuscole e minuscole non contano). Il nome è quello della gilda in gioco, letto dal client del GM |
| D20 | Stile pergamena di WoW, con priorità alla leggibilità |
| D21 | V1: pulsante sulla minimappa, `/gf` e tasto rapido; integrazione nelle finestre di Blizzard più avanti |
| D22 | V1 in inglese, con la localizzazione predisposta |
| D23 | Ace3 e LibDBIcon nelle versioni compatibili con il client |
| D24 | Addon non ufficiale, scaricato e installato a mano |
| D25 | Specifiche nel repository, un file per argomento, con i bozzetti prima dello sviluppo |
| D26 | V1 = ricerca, filtri, pagina della gilda, annunci e candidature |

## 7. Glossario

- **Annuncio (listing)**: la scheda pubblica di una gilda nel catalogo.
- **Catalogo**: l'insieme degli annunci che un client conosce, salvato nelle SavedVariables.
- **Peer**: un altro client con l'addon, collegato al canale dell'addon.
- **Contatto della gilda**: il GM o un ufficiale online con l'addon, che può ricevere le candidature.
- **Personaggio attivo**: un personaggio della gilda entrato in gioco negli ultimi 7 giorni.
- **Giocatore unico**: un account distinto tra i personaggi attivi. È una stima, perché si può contare solo chi usa l'addon ([SPEC-03 §4](SPEC-03-data-model.md#4-statistiche)).
