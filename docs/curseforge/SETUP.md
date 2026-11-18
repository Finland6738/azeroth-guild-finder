# Guida: creare la pagina CurseForge di Azeroth Guild Finder

Guida passo passo per il proprietario. Tutto il testo da incollare è in inglese (la pagina è pubblica) ed è già pronto in questa cartella. **Non è ancora stato creato nulla su CurseForge.** Il resto del flusso di rilascio (tag, workflow) è in [docs/RELEASING.md](../RELEASING.md): qui non lo ripeto.

Come riferimento ho usato la pagina di Azeroth Unspoken: riepilogo di una riga, descrizione con titolo, paragrafo introduttivo, sezioni di funzioni, privacy, compatibilità, stato di sviluppo, link al codice; categorie, galleria con 14 immagini, link *Wiki* e *Source*, versione di gioco *WoW Forever* (flavor *Forever*, versione 1.60.1).

## File di questa cartella

| File | Dove si usa |
|---|---|
| `summary.txt` | campo *Summary* (195 caratteri, il limite di CurseForge è 250) |
| `description.md` | campo *Description* |
| `gallery/logo.png` | logo del progetto (400×400) |
| `gallery/01…08-*.jpg` + `gallery/CAPTIONS.md` | galleria, in ordine, con didascalie |
| `changelog-first-release.md`, `short-description.txt` | note di rilascio del primo file |

## 1. Creare il progetto

1. Accedi a CurseForge e vai su <https://www.curseforge.com/wow/addons>, poi **Create project** (menu *Create*). Scegli il gioco **World of Warcraft** e il tipo **Addons**.
2. **Name**: `Azeroth Guild Finder`. Lo *slug* (URL) diventa `azeroth-guild-finder`: lascia quello proposto, non si cambia facilmente dopo.
3. **Summary**: incolla `summary.txt`.
4. **Categories** (scegli quelle che CurseForge offre, come per Unspoken: una principale e al massimo qualche secondaria): *Chat & Communication* e *Miscellaneous*; se esiste *Guild* (o simile) aggiungila come principale.
5. **License**: *GNU General Public License version 3 (GPL-3.0)*, la stessa del repository.
6. **Game versions / flavor**: **WoW Forever**, come Unspoken. Il file caricato dal workflow porta la versione dal TOC (`## Interface: 16001`); dopo il primo upload controlla che sia segnato *Forever*.
7. **Description**: incolla `description.md`.
   - Non ho potuto verificare l'editor (serve l'accesso). L'editor di CurseForge è un editor ricco (WYSIWYG): se il Markdown incollato appare come testo con `#` e `**`, applica titoli, elenchi e grassetto con la barra degli strumenti (titoli = *Heading*, tabelle dei comandi come elenco). Controlla l'anteprima prima di salvare.
8. **Links**: *Source* `https://github.com/Finland6738/azeroth-guild-finder`; *Issues* `https://github.com/Finland6738/azeroth-guild-finder/issues`; *Wiki* `https://github.com/Finland6738/azeroth-guild-finder/wiki`; donazioni **Ko-fi**: `https://ko-fi.com/finland6738` (campo *Donations*).
9. **Logo**: carica `gallery/logo.png`.
10. Salva. Il progetto resta in bozza finché non carichi un file o lo invii in revisione: CurseForge fa una moderazione prima della pubblicazione.

## 2. Galleria

Dalla scheda *Images* carica le otto immagini **nell'ordine del numero** (la prima è la copertina) e incolla titolo/didascalia da `gallery/CAPTIONS.md`. Le immagini sono **bozzetti di design**, non schermate del gioco: la didascalia dice "design preview" e la descrizione lo ripete. Sostituiscile dopo M5.6 (sezione 6).

## 3. ID del progetto

Dopo la creazione, il **Project ID** è un numero nel riquadro *About Project* della pagina (come `1791391` per Unspoken). Poi, come in [RELEASING.md](../RELEASING.md#setting-up-curseforge-once) passo 2, in `AzerothGuildFinder/AzerothGuildFinder.toc` cambia `# ## X-Curse-Project-ID: 0` in `## X-Curse-Project-ID: <numero>` (due `#`, nessuno spazio davanti) e fai una PR normale.

## 4. Token API e segreto `CF_API_KEY`

Lo fai **tu**; non incollare mai il token in chat, in una issue o in una PR.

1. Apri <https://www.curseforge.com/account/api-tokens> e crea un token.
2. Su GitHub, repository → **Settings → Secrets and variables → Actions → New repository secret**: nome `CF_API_KEY`, valore il token.

Finché mancano sia l'ID nel TOC sia il segreto, i tag pubblicano solo su GitHub.

## 5. Primo tag beta

Dopo l'ID e il segreto, e dopo la prova su GitHub (vedi RELEASING.md, "Try it without publishing anything"), pubblica un tag di pre-release, ad esempio `v0.9.0-beta.1`:

```bash
git tag -a v0.9.0-beta.1 -m "First beta"
git push origin v0.9.0-beta.1
```

Poi apri il file su CurseForge: verifica il tipo *Beta*, la versione di gioco *WoW Forever*, e incolla `changelog-first-release.md` come note (o `short-description.txt` se vuoi una riga sola). Questo passaggio crea un rilascio pubblico: fallo solo quando sei pronto per M5.6.

## 6. Schermate vere da fare dopo M5.6

Servono per sostituire i bozzetti. Risoluzione 1280×800 o più, interfaccia al 100%, personaggi di prova senza nomi reali di altri giocatori (nelle liste usa i dati finti).

| # | Cosa catturare | Come arrivarci |
|---|---|---|
| 1 | Find a Guild con filtri e lista | personaggio **senza gilda**, `/gf`, scheda *Find a Guild*; per una lista piena `/gf debug seed 60` (solo build di sviluppo, `/gf debug seed clear` la toglie) |
| 2 | Pagina di una gilda | clic su una gilda della lista; mostra "looking for", statistiche, requisiti |
| 3 | Editor dell'annuncio | Guild Master: `/gf`, *My Guild* → *Edit listing* (o `/gf debug editor`) |
| 4 | Passo *Activity* dell'editor | nell'editor, passo delle attività con 3 scelte |
| 5 | Designer dello stemma | editor, passo *Identity*, *Design an emblem* (e una con stemma dal tabard) |
| 6 | Pannello candidature | ufficiale: `/gf`, scheda *Applications*, con qualche candidatura (due personaggi di prova che si candidano) |
| 7 | Icona di notifica | ufficiale con candidatura in attesa: icona mobile con badge e lista rapida (`/gf notify` per mostrarla/nasconderla) |
| 8 | Impostazioni | `/gf`, scheda *Settings* (al posto della tavola degli stati) |

Quando le hai, salvale in `docs/curseforge/gallery/`, aggiorna `CAPTIONS.md` (togli "design preview") e il paragrafo *Development status* di `description.md`.
