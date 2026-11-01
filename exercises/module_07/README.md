# Exercice du module 7

Objectif : compter les votes du cluster Windows du cours et dire, pour quatre pannes, si le
quorum tient, à partir de ses sorties réelles.

L'exercice ne demande ni Windows ni conteneur. Il lit `data/cluster/`, les sorties du cluster
des vidéos (deux nœuds, `SQL01` et `SQL02`, et le groupe `Pacha`), un dossier par état :
`start` pour le cluster sain, `with-witness` pour le même cluster avec un témoin de partage de
fichiers, et un dossier par panne. `data/cluster/events.txt` donne l'heure UTC de chaque
coupure et de chaque remise en marche.

## Les fichiers

- `1-start.sh` écrit `exercises/module_07/answers.txt`, une réponse vide par ligne, et
  remplace le fichier s'il existe. Ce fichier est ignoré par git.
- `check.sh` compare les réponses à ce que disent les fichiers de `data/cluster/`. Il ne
  contient pas les réponses : il les calcule, depuis les votes comptés (`DynamicWeight`) des
  nœuds `Up`, le vote du témoin, et la majorité qui reste après la perte d'un nœud.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. Il écrit les réponses,
  puis ajoute à `evidence/module_07.md` les délais mesurés sur les fichiers.

```bash
./exercises/module_07/1-start.sh
./exercises/module_07/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Dans `data/cluster/start`, lisez `quorum.txt`, `cluster.txt` et `nodes.txt`. Combien de
   votes comptent, et quel nœud les a ? Remplissez `votes` et `voters`.
3. Pour chaque panne, partez du cluster sain et répondez `kept` ou `lost` : coupure de
   `SQL01`, coupure de `SQL02`, arrêt propre de `SQL02`, puis coupure de `SQL02` dans la
   configuration `with-witness`.
4. Dans `data/cluster/sql02-power-loss/cluster-log-SQL01.txt`, trouvez l'heure UTC
   (`HH:MM:SS`) à laquelle `SQL01` a perdu le quorum.
5. Lancez `check.sh`. Il sort en 0 quand tout tient.

---

# Exercise of module 7

Goal: count the votes of the course's Windows cluster and say, for four failures, whether the
quorum holds, from its real outputs in `data/cluster/`. No Windows and no container needed.
Run `1-start.sh`, fill `exercises/module_07/answers.txt`, then run `check.sh`, which computes
the expected answers from the files and exits 0 when every answer matches.
`solution/2-solution.sh` is a worked solution.
