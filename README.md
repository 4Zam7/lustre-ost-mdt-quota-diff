# lustre-ost-mdt-quota-diff

Scripts shell pour comparer les quotas Lustre par OST/MDT **avant et après** un `force_reint`, afin de détecter les dérives, les quotas corrompus, et les cibles saturées.

---

## Contexte et problématique

Sur un système de fichiers Lustre, les quotas sont comptabilisés localement par chaque OSD (Object Storage Device) sur les OSTs et MDTs. Il arrive que ces compteurs locaux se désynchronisent du quota global — par exemple après une panne, une migration de données, ou une opération de maintenance — ce qui peut conduire à des **valeurs de limit incorrectes** (gonflées artificiellement ou en dessous du réel).

La commande :

```bash
sudo clush -bw @vmds,@voss 'lctl set_param osd-ldiskfs.*.quota_slave.force_reint=1'
```

force une **réinitialisation et recalcul** des quotas sur tous les VMs de données (VMDs) et OSS (Object Storage Servers). Elle relit l'ensemble des blocs présents sur chaque OST/MDT et recalcule les limites de manière cohérente.

Ces scripts permettent de **visualiser l'impact de ce recalcul** en comparant deux sorties de la commande :

```bash
sudo lfs quota -v -p <pid> <filesystem>
```

prises respectivement **avant** et **après** le `force_reint`.

---

## Prérequis

- **OS** : Linux ou macOS (compatible bash 3+, awk POSIX, grep BSD)
- **Outils requis** : `bash`, `awk`, `grep` — tous natifs, aucune dépendance externe
- **Droits** : aucun droit particulier pour exécuter les scripts ; les droits `sudo` sont nécessaires pour générer les fichiers d'entrée sur le cluster Lustre
- **Fichiers d'entrée** : deux fichiers texte contenant la sortie de `lfs quota -v`

---

## Génération des fichiers d'entrée

### Étape 1 — Capturer le quota avant le force_reint

```bash
sudo lfs quota -v -p <pid> <filesystem> > quota_before.txt
```

Exemple :

```bash
sudo lfs quota -v -p 334 /fsdata/scratch/users/jdupont/ > quota_before.txt
```

### Étape 2 — Lancer le force_reint sur tous les nœuds de stockage

```bash
sudo clush -bw @vmds,@voss 'lctl set_param osd-ldiskfs.*.quota_slave.force_reint=1'
```

> Cette commande déclenche le recalcul des quotas sur l'ensemble des OSTs et MDTs. Selon la taille du filesystem et le nombre d'objets, l'opération peut prendre quelques minutes.

### Étape 3 — Capturer le quota après le force_reint

```bash
sudo lfs quota -v -p <pid> <filesystem> > quota_after.txt
```

Exemple :

```bash
sudo lfs quota -v -p 334 /fsdata/scratch/users/jdupont/ > quota_after.txt
```

---

## Installation

```bash
git clone https://github.com/<votre-user>/lustre-ost-mdt-quota-diff.git
cd lustre-ost-mdt-quota-diff
chmod +x lustre-sto-quota-diff_ko.sh
chmod +x lustre-sto-quota-diff_mo.sh
chmod +x lustre-sto-quota-diff_go.sh
```

---

## Utilisation

Trois scripts sont disponibles selon l'unité souhaitée :

| Script | Unité | Précision |
|---|---|---|
| `lustre-sto-quota-diff_ko.sh` | Kilo-octets (Ko) | entier |
| `lustre-sto-quota-diff_mo.sh` | Méga-octets (Mo) | 1 décimale |
| `lustre-sto-quota-diff_go.sh` | Giga-octets (Go) | 2 décimales |

### Syntaxe

```bash
./lustre-sto-quota-diff_<unité>.sh <before_file> <after_file>
```

### Exemples

```bash
./lustre-sto-quota-diff_go.sh quota_before.txt quota_after.txt
./lustre-sto-quota-diff_mo.sh quota_before.txt quota_after.txt
./lustre-sto-quota-diff_ko.sh quota_before.txt quota_after.txt
```

---

## Lecture du tableau de sortie

```
║ Filesystem                   │  Go utilise │ limit av. (Go) │ limit ap. (Go) │   Δ limit (Go) ║
║ fsdata-OST0013_UUID          │       75.61 │         302.95 │          79.61 │        -223.34 ║
```

| Colonne | Description |
|---|---|
| **Filesystem** | Nom de l'OST ou MDT |
| **Go utilisé** | Espace réellement consommé (identique avant/après, le force_reint ne touche pas les données) |
| **limit av.** | Limite de quota **avant** le force_reint |
| **limit ap.** | Limite de quota **après** le force_reint (valeur recalculée) |
| **Δ limit** | Différence entre limit ap. et limit av. — en vert si hausse, en rouge si baisse |

### Codes couleur

| Couleur | Signification |
|---|---|
| 🟢 Vert | La limite a augmenté après recalcul |
| 🔴 Rouge | La limite a diminué — souvent signe d'une valeur corrompue corrigée |
| Blanc `=` | Aucun changement |
| `(sature)` | L'espace utilisé est égal ou supérieur à la limite — OST/MDT plein |

### Résumé en bas de sortie

```
Résumé :
  Entrées avec limit modifiée  : 77
  Entrées inchangées           : 7
  (sature) OSTs/MDTs saturés (utilisé >= limit) : 5

  Total allocated block limit avant : 2047.91 Go
  Total allocated block limit après : 1411.45 Go
  Delta total                       : -636.46 Go
```

---

## Interpréter les cas particuliers

### Δ limit fortement négatif (rouge)

```
fsdata-OST0013_UUID  │  75.61  │  302.95  │  79.61  │  -223.34
```

La limite avant était **corrompue à 302.95 Go** alors que seulement 75.61 Go sont utilisés. Après le force_reint, la limite a été **recalculée à 79.61 Go** (utilisation réelle + marge). Le Δ négatif indique une **correction de quota erroné**, ce qui est le comportement attendu.

### OST saturé `(sature)`

```
fsdata-OST0008_UUID  │  73.87  │  73.87  │  73.87  │  = (sature)
```

L'espace utilisé est égal à la limite. L'OST est plein physiquement — le force_reint n'a pas pu augmenter la limite car il n'y a plus de place disponible. **Action recommandée** : libérer de l'espace ou étendre la capacité de l'OST.

### Δ limit légèrement positif (+4 Go typiquement)

```
fsdata-OST0000_UUID  │  0.37  │  0.37  │  4.37  │  +4.00
```

Le recalcul a correctement alloué une marge au-dessus de l'utilisation réelle (~4 GiB), comportement normal pour des OSTs peu remplis.

---

## Fichiers du repo

```
lustre-ost-mdt-quota-diff/
├── README.md
├── lustre-sto-quota-diff_ko.sh   # Version Ko
├── lustre-sto-quota-diff_mo.sh   # Version Mo
└── lustre-sto-quota-diff_go.sh   # Version Go
```

---

## Voir aussi

- [lustre-project-quota-diff](https://github.com/4Zam7/Lustre-quota-diff) — scripts de comparaison de quotas Lustre au niveau **projet**

---

## Licence

MIT
