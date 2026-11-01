# Exercice du module 4

Objectif : mesurer sur votre machine le prix d'une validation synchrone, en jouant le même
lot de 2 000 `INSERT` avec `hadrlab2` en validation synchrone puis en validation asynchrone, et
rendre ensuite le groupe dans son état de départ.

L'exercice crée sa base, `ex_commit`, l'ajoute au groupe `AgPacha` et n'écrit rien d'autre sur
le labo. `demos/module_04/99-cleanup.sh` retire le groupe et supprime la base à la fin du
module.

## Les fichiers

- `1-start.sh` vérifie que le groupe `AgPacha` existe, et le crée avec `PachadataTraining` s'il
  manque (`setup/ag-create.sh`). Il remet `hadrlab2` en validation synchrone si un essai
  précédent l'a laissé en asynchrone. Il crée ensuite `ex_commit` sur `hadrlab1`, la sauvegarde,
  l'ajoute au groupe et attend que les deux copies soient à jour. La base contient :
  - `dbo.Registration`, où le lot écrit, une ligne par `INSERT`, avec le nom du lot ;
  - `dbo.Measure`, une ligne par lot ;
  - `dbo.RunBatch @batch`, qui joue 2 000 `INSERT` d'une ligne, chacun dans sa propre
    transaction, et écrit dans `dbo.Measure` le mode de validation de `hadrlab2` au début du
    lot, la durée, et les attentes `HADR_SYNC_COMMIT` de sa session (nombre et millisecondes).

  Le relancer retire la base du groupe, la supprime des trois instances et repart de zéro.
- `check.sh` lit l'état de `hadrlab1` et dit ce qui manque.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. D'autres réponses sont
  justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_04/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_04/1-start.sh
./exercises/module_04/check.sh         # avec Podman : ENGINE=podman ./exercises/module_04/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Lisez `dbo.RunBatch` (`sp_helptext`, ou `1-start.sh`) : que mesure-t-il, et sur quelle
   session ?
3. Sur `hadrlab1`, `hadrlab2` étant synchrone et `SYNCHRONIZED`, lancez
   `EXEC ex_commit.dbo.RunBatch @batch = 'synchronous';`.
4. Passez `hadrlab2` en validation asynchrone. Avant de mesurer, vérifiez dans l'état du groupe
   que le primaire ne l'attend plus.
5. Lancez le même lot sous un autre nom, par exemple `'asynchronous'`.
6. Remettez `hadrlab2` en validation synchrone, et attendez que sa copie de `ex_commit` soit de
   nouveau `SYNCHRONIZED`, en lisant l'état sur le primaire, pas en comptant les secondes.
7. Lancez `check.sh`. Il sort en 0 quand tout tient.

`check.sh` vérifie, sur `hadrlab1`, que `ex_commit` est une base du groupe ; qu'il existe une
mesure prise avec `hadrlab2` en `SYNCHRONOUS_COMMIT`, avec ses 2 000 lignes et au moins une
attente `HADR_SYNC_COMMIT` ; qu'il en existe une prise en `ASYNCHRONOUS_COMMIT`, avec ses
2 000 lignes ; que la mesure asynchrone compte moins d'attentes `HADR_SYNC_COMMIT` que la
synchrone ; et que `hadrlab2` est revenu en `SYNCHRONOUS_COMMIT`, sa copie `SYNCHRONIZED`. Il ne
compare aucune durée : sur une machine chargée, le lot synchrone peut sortir plus rapide d'un
essai à l'autre.

## À réfléchir

- Divisez l'écart de durée entre les deux lots par le nombre d'attentes `HADR_SYNC_COMMIT` :
  combien chaque validation a-t-elle payé ? Le temps total de ces attentes explique-t-il tout
  l'écart ?
- Si la mesure synchrone ne compte aucune attente, qu'est-ce que cela dit de `hadrlab2` à ce
  moment-là ?
- Notez vos deux durées : le dernier module du cours les reprend. Le corrigé les ajoute à
  `evidence/module_04.md`.
