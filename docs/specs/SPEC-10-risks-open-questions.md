# SPEC-10: Rischi e domande aperte

## 1. Rischi

| ID | Rischio | Probabilità | Impatto | Mitigazione |
|---|---|---|---|---|
| R1 | I personaggi di livello basso non possono inviare nel canale (osservato da OneForAll): proprio il pubblico dell'addon | alta | alto | modo solo ascolto, WHISPER, contatti Discord; spike S3/S4 |
| R2 | Pochi utenti dell'addon: catalogo scarso, sincronizzazione lenta | media | alto | cache permanente; ogni membro di una gilda pubblicata ripete l'annuncio; il GM può invitare la gilda a installare l'addon |
| R3 | Annunci falsificati (modello P2P) | bassa | medio | INT-01…INT-06; firma nella V2 se serve |
| R4 | Il nome del canale non si può cambiare dopo il rilascio | certa | medio | nome deciso ora; il protocollo si aggiorna con `PROTO`, non con il canale |
| R5 | Cambi di Blizzard alle restrizioni degli addon (lockdown, valori segreti) | media | medio | layer Compat, verifica delle funzionalità con `/gf debug`, code di invio |
| R6 | Limite di 10 canali personalizzati per personaggio: se sono già tutti usati, l'entrata fallisce | bassa | alto | avviso chiaro con istruzioni; modo solo cache |
| R7 | `C_ClubFinder` attivo su Forever (in questo caso è un rischio positivo) | ? | alto | spike S1 prima di tutto |
| R8 | Traffico eccessivo in ore di punta | bassa | medio | soppressione, budget NET-01…04, simulatore |

## 2. Domande aperte per te

| # | Domanda | Proposta |
|---|---|---|
| Q1 | ~~Nome dell'addon e del canale~~ | **Deciso (2026-11-08)**: "Azeroth Guild Finder", cartella `AzerothGuildFinder`, canale `AzGuildFinder`, prefisso `AzGF`, comando `/gf` |
| Q2 | ~~Una candidatura aperta: per personaggio o per account~~ | **Deciso**: per personaggio |
| Q3 | ~~Scadenza e attesa dopo un rifiuto~~ | **Deciso**: 14 giorni e 7 giorni |
| Q4 | ~~Ruoli nella candidatura~~ | **Deciso**: 4 caselle facoltative (Tank, Healer, Melee, Ranged), nessun testo libero |
| Q5 | ~~Giocatori unici come intervallo~~ | **Deciso**: intervallo con la spiegazione |
| Q6 | ~~Condivisione anonima del numero di personaggi~~ | **Deciso**: attiva di base, si può disattivare |
| Q7 | ~~Licenza del codice~~ | **Decisa: GPL-3.0** ([ADR 0017](../adr/0017-license-gpl-3.md)) |
| Q8 | ~~Lingua della documentazione~~ | **Decisa**: inglese per README, wiki e ADR; italiano per queste specifiche ([ADR 0016](../adr/0016-english-first-ui-and-documentation-languages.md)) |
| Q9 | ~~Workflow Git~~ | **Deciso**: come azeroth-unspoken, con commit, push, PR e merge automatici ([ADR 0013](../adr/0013-git-flow-and-automated-shipping.md)) |
