# SPEC-03: Modello dati

## 1. Identità di una gilda

```lua
guildKey = realm .. "|" .. faction .. "|" .. guildName
-- realm:     GetNormalizedRealmName()           (es. "Firemaw")
-- faction:   UnitFactionGroup("player")         "Alliance" | "Horde"
-- guildName: GetGuildInfo("player"), esattamente come in gioco [verificare]
```

- Il nome **non si scrive mai a mano**: l'editor lo legge dal client del GM (D19). Se la gilda viene rinominata (esiste `C_GuildInfo.RequestGuildRename`), il GM ripubblica l'annuncio: la chiave nuova sostituisce la vecchia, e la vecchia diventa un `DEL`.
- Il client mostra **solo** la propria fazione e il proprio reame (D4, D5): gli annunci di altre fazioni o reami ricevuti per errore vengono scartati.
- Una voce del catalogo può essere **solo locale** (`localOnly`, usata da `/gf debug seed` nelle build di sviluppo): si vede nella lista ma non entra mai nel digest né nelle risposte `CAT`, quindi non viene condivisa.

## 2. Annuncio: riassunto (viaggia negli `ANN` e nei `CAT`)

| Campo | Tipo | Limiti | Note |
|---|---|---|---|
| `k` | string | ≤ 80 | `guildKey` |
| `rev` | int | ≥ 1 | aumenta a ogni modifica del contenuto da parte del GM |
| `upd` | int | epoch UTC | ora dell'ultima modifica (`GetServerTime()`) |
| `first` | int | epoch UTC | prima pubblicazione: mostrata come "Listed since" |
| `own` | string | 8 esadecimali | `ownerId` (INT-03) |
| `sub` | string | ≤ 60 caratteri | sottotitolo |
| `lang` | int | bitmask | lingue: la principale è `lang1`, le secondarie in `lang` |
| `lang1` | int | indice | lingua principale |
| `tags` | array di int | 1–3 voci, senza doppioni | tipi di attività in ordine di importanza (§5) |
| `pace` | int | 1/2/3 | impegno: Casual / Softcore / Hardcore (§5) |
| `days` | int | bitmask 7 bit | giorni di attività, da lunedì a domenica |
| `t0`, `t1` | int | 0–1439 | inizio e fine in **minuti UTC**; `t0 == t1` significa tutto il giorno (come in Albion) |
| `rec` | int | 0/1/2 | reclutamento: chiuso / aperto / solo alcune classi o ruoli |
| `apps` | bool | | candidature dall'addon aperte (D7) |
| `want` | table | ≤ 30 voci | classi e ruoli cercati: `{ [classID] = rolesMask }`, dove `rolesMask` contiene Tank=1, Healer=2, Melee DPS=4, Ranged DPS=8; `{ [0] = rolesMask }` significa qualsiasi classe |
| `newb` | bool | | gilda aperta ai nuovi giocatori |
| `minL` | int | 1–livello massimo | livello minimo |
| `minI` | int | 0–999 | livello medio minimo dell'equipaggiamento, 0 = nessuno (facoltativo, D11) |
| `emb` | table | indici 0–1023, colori 0–0xFFFFFF | stemma: `t` (1 tabarro, 2 composto), indici del catalogo `e`, `b`, `g` e colori RGB `gc`, `bc`, `ec` ([SPEC-08 §2](SPEC-08-assets-emblems-l10n.md#2-stemma)) |
| `bg` | int | indice | sfondo scelto dal catalogo verificato ([SPEC-08 §3](SPEC-08-assets-emblems-l10n.md#3-sfondi)) |
| `st` | table | | statistiche (§4) |
| `srev` | int | epoch UTC | ora del calcolo delle statistiche, arrotondata all'ora |
| `test` | bool | | annuncio di prova inviato da `/gf debug announce` in una build di sviluppo; le build di rilascio lo ignorano (SPEC-02 §6) |

Dimensione stimata: circa 160 byte in CBOR, circa 120 compressi.

## 3. Annuncio: dettaglio (viaggia in `DET` e `GLIST`)

| Campo | Tipo | Limiti | Note |
|---|---|---|---|
| `k`, `rev` | | | come nel riassunto |
| `desc` | string | ≤ 500 caratteri, ≤ 12 righe | descrizione |
| `disc` | string | 2–32 caratteri `[A-Za-z0-9-]` | **solo il codice** d'invito Discord; l'interfaccia mostra `https://discord.gg/<codice>` (D13) |
| `cont` | table | ≤ 3 nomi | personaggi da contattare, scelti dal roster della gilda |
| `note` | string | ≤ 120 caratteri | nota sui requisiti, per esempio "Voice chat required for raids" |

## 4. Statistiche

Calcolate **dal client di ciascun membro** che fa un `ANN`, usando il roster della gilda (fonte del server) e i token `GTOK`. Vince la versione con lo `srev` più recente. **Si pubblicano solo numeri aggregati** (D12).

| Campo | Significato | Fonte |
|---|---|---|
| `m` | membri totali | `GetNumGuildMembers()` [verificare] |
| `a7` | **personaggi attivi**: entrati in gioco negli ultimi 7 giorni | `GetGuildRosterLastOnline(i)` o `ClubMemberInfo.lastOnline*`, più i membri online ora |
| `u7lo`, `u7hi` | **giocatori unici attivi**, come intervallo stimato | token `GTOK` (sotto) |
| `max` | personaggi attivi al livello massimo | `level == GetMaxPlayerLevel()` [verificare] |
| `cls` | distribuzione delle classi tra i personaggi attivi `{ [classID] = n }` | roster |

### Giocatori unici: token anonimi

Il client non può sapere quali personaggi appartengono allo stesso account. Per stimarlo:

1. Ogni installazione ha un `accountSecret` casuale, salvato nelle SavedVariables dell'account e **mai inviato**.
2. Per ogni gilda il client calcola `token = hash(accountSecret .. guildKey)`. È diverso per ogni gilda, quindi un account non si può seguire da una gilda all'altra.
3. Al login, e ogni 24 h, invia nel canale `GUILD` un messaggio `GTOK{ token, n }`, dove `n` è il **numero** (non i nomi) dei personaggi di quell'account nella gilda attivi negli ultimi 7 giorni. Con `want = 1` gli altri membri online rispondono col proprio `GTOK`, dopo un ritardo casuale di 1–20 s.
4. Ogni membro conserva i token ricevuti per 7 giorni.
5. Calcolo: `coperti = somma di n`; `scoperti = max(0, a7 − coperti)`;
   `u7lo = token distinti + (scoperti > 0 and 1 or 0)`; `u7hi = token distinti + scoperti`.

L'interfaccia mostra "Unique players: 14" se `u7lo == u7hi`, altrimenti "Unique players: 12–18", con la spiegazione nel tooltip: "Estimated: counted exactly among members who use the addon".

Riservatezza: i compagni di gilda vedono solo che un membro ha *n* personaggi attivi, non quali. Un'impostazione ("Share anonymous alt count with my guild", attiva di base) permette di non inviare `GTOK`.

### Data di fondazione (D12)

Il client non offre un'API che dia la data di fondazione della gilda in modo affidabile. **Nella V1 non viene mostrata.** Al suo posto la pagina mostra "Listed since" (`first`) e "Updated" (`upd`), che sono date certe.

## 5. Elenchi chiusi (configurabili in un solo file, `Data/Enums.lua`)

**Lingue** (bit): English, German, French, Spanish, Italian, Portuguese, Russian, Polish, Other.

**Tipi di attività** (`tags`): il GM ne sceglie **da 1 a 3**, in ordine di importanza; il primo è l'attività principale. Ogni voce ha un'icona del gioco, scelta e registrata nello spike. L'elenco va confrontato con i contenuti realmente presenti su Forever prima del rilascio: le voci marcate [verificare] spariscono se il contenuto non c'è.

| # | Etichetta (UI) | Significato |
|---|---|---|
| 1 | Raids | incursioni a 10/20/40 giocatori |
| 2 | Dungeons | spedizioni a 5 giocatori |
| 3 | Leveling | salire di livello insieme, aiutare i nuovi |
| 4 | Questing & Exploration | missioni, zone, storia del mondo |
| 5 | Battlegrounds | campi di battaglia organizzati |
| 6 | World PvP | PvP nel mondo aperto, imboscate, raid sulle città |
| 7 | Professions & Crafting | professioni, creazione di oggetti |
| 8 | Gold & Trading | casa d'aste, commercio |
| 9 | Reputation & Collecting | reputazioni, cavalcature, oggetti rari |
| 10 | Roleplay | gioco di ruolo |
| 11 | Social & Chat | compagnia, chiacchiere, Discord |
| 12 | Events & Community | eventi di gilda, festività, raduni |
| 13 | Housing [verificare] | casa del giocatore e quartiere, se Forever lo prevede (il client ha le API `Housing*`) |

**Impegno** (`pace`, obbligatorio, una sola scelta):

| Valore | Etichetta | Significato (mostrato nel tooltip) |
|---|---|---|
| 1 | **Casual** | si gioca quando si può, nessun impegno fisso |
| 2 | **Softcore** | attività regolari e qualche evento in calendario; la presenza è gradita ma non obbligatoria |
| 3 | **Hardcore** | calendario impegnativo, presenza richiesta, preparazione attesa (consumabili, equipaggiamento) |

"Hardcore" indica qui l'**impegno della gilda**, non la modalità con morte permanente. Se Forever avesse reami con morte permanente, il tooltip lo dice esplicitamente [verificare].

**Classi**: ricavate dal client (`C_CreatureInfo.GetClassInfo` / `GetNumClasses` [verificare]), non scritte nel codice, così l'elenco segue quello che il gioco offre. Nell'editor e nei filtri compaiono solo le classi giocabili dalla propria fazione (nel gioco originale Paladino solo Alleanza e Sciamano solo Orda) [verificare su Forever]. Le combinazioni classe-ruolo impossibili sono disattivate (tabella in `Data/Enums.lua`).

**Ruoli**: Tank, Healer, **Melee DPS**, **Ranged DPS**. Il DPS è diviso perché una gilda che cerca "DPS" di solito ne cerca di un tipo preciso (a distanza: Hunter, Mage, Warlock, Priest Shadow, Shaman Elemental, Druid Balance).

Combinazioni classe-ruolo ammesse (le altre sono disattivate nell'editor e nei filtri); va confermata con i contenuti di Forever:

| Classe | Tank | Healer | Melee | Ranged |
|---|:-:|:-:|:-:|:-:|
| Warrior | ✓ | | ✓ | |
| Paladin | ✓ | ✓ | ✓ | |
| Hunter | | | | ✓ |
| Rogue | | | ✓ | |
| Priest | | ✓ | | ✓ |
| Shaman | | ✓ | ✓ | ✓ |
| Mage | | | | ✓ |
| Warlock | | | | ✓ |
| Druid | ✓ | ✓ | ✓ | ✓ |

## 6. Validazione

Ogni record ricevuto o salvato passa da `Sanitize`, come nell'ADR 0006 di azeroth-unspoken: tipi controllati, numeri riportati nei limiti, stringhe tagliate alla lunghezza massima, valori fuori dagli elenchi scartati. Un record senza `k` valido o senza `rev` viene scartato per intero.

Testi (`sub`, `desc`, `note`):

- `|` diventa `||`, così niente codici di colore, link o texture;
- vengono tolti i caratteri di controllo tranne `\n` (solo in `desc`);
- la lunghezza si conta in **caratteri UTF-8**, non in byte.
- `Sanitize` è **idempotente**: una sequenza di `|` viene portata a lunghezza pari (`|` → `||`, `||` resta `||`, `|||` → `||||`), così un record già ripulito non si raddoppia al secondo passaggio; la lunghezza massima si applica al testo già con `||` e non spezza mai una coppia;
- i campi sconosciuti vengono scartati; un campo non valido viene omesso (i numeri fuori limite, dove il §2 dà un intervallo, vengono riportati nei limiti); `Listing.IsComplete` dice se il riassunto ha lingua principale, 1–3 tipi di attività e `pace`;
- `k` è valido se ha la forma `reame|Alliance|nome` oppure `reame|Horde|nome` (≤ 80 caratteri, senza `|` nel nome e senza caratteri di controllo).

Il codice Discord deve corrispondere a `^[A-Za-z0-9%-]{2,32}$`. Se il GM incolla un link intero (`https://discord.gg/abc`, `discord.com/invite/abc`), l'editor estrae da solo il codice.

## 7. Normalizzazione dei nomi (ordinamento e ricerca, D19)

```
sortKey(nome):
  1. sostituisce le lettere accentate con quelle base (à→a, é→e, ö→o, ñ→n, ç→c, ß→ss, æ→ae, œ→oe…)
  2. mette tutto in minuscolo
  3. elimina tutto ciò che non è a–z (spazi, numeri, simboli, trattini, trattini bassi)
```

- La lista è **sempre** ordinata per `sortKey` crescente; a parità si confronta il nome originale. I nomi con `sortKey` vuoto (solo simboli o numeri) vanno in fondo.
- La ricerca per nome normalizza allo stesso modo la query e cerca una **sottostringa** di `sortKey`. Servono almeno **3 lettere** dopo la normalizzazione, come in Albion ("Spaces, underscores and hyphens are ignored").
- Il nome **mostrato** resta sempre quello originale, con accenti e spazi.

Esempi: `"Ördine del Drago"` → `ordinedeldrago`; `"[AD] GankEmAll"` → `adgankemall`; `"wjwkskjs i"` → `wjwkskjsi`.

## 8. Candidatura

| Campo | Tipo | Note |
|---|---|---|
| `id` | string | 8 esadecimali casuali |
| `k` | string | `guildKey` |
| `who` | string | `Nome-Reame` del personaggio |
| `cls`, `race`, `lvl` | int | letti dal client al momento dell'invio |
| `ilvl` | int | livello medio dell'equipaggiamento, se l'API esiste |
| `roles` | int | facoltativo: ruoli indicati dal candidato (Tank=1, Healer=2, Melee=4, Ranged=8), solo quelli validi per la classe |
| `at` | int | epoch UTC dell'invio |
| `state` | enum | `sent`, `received`, `accepted`, `declined`, `withdrawn`, `expired` |
| `stateRev` | int | aumenta a ogni cambio di stato |
| `by` | string | chi ha deciso (visibile solo a GM e ufficiali) |

Ciclo di vita e regole in [SPEC-07](SPEC-07-applications.md).
