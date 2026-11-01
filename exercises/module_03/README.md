# Exercice du module 3

Objectif : protéger une seconde base, `ex_inscriptions`, par le groupe `AgPacha`, avec une copie
créée par seeding automatique sur `hadrlab2` et sur `hadrlab3`.

L'exercice crée sa base, `ex_inscriptions`, et n'écrit rien d'autre sur le labo.
`demos/module_03/99-cleanup.sh` retire le groupe et supprime la base à la fin du module.

## Les fichiers

- `1-start.sh` vérifie que le groupe `AgPacha` existe, et le crée avec `PachadataTraining` s'il
  manque (`setup/ag-create.sh`). Il crée ensuite `ex_inscriptions` sur `hadrlab1`, en mode de
  récupération complet, jamais sauvegardée : une table `dbo.Registration` de 100 lignes, et un
  dossier vide sur le volume partagé, `/var/opt/mssql/share/ex_inscriptions`, pour ses
  sauvegardes. Le relancer retire la base du groupe, la supprime des trois instances et repart
  de zéro.
- `check.sh` lit l'état des trois instances et dit ce qui manque.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. D'autres réponses sont
  justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_03/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_03/1-start.sh
./exercises/module_03/check.sh         # avec Podman : ENGINE=podman ./exercises/module_03/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Essayez d'ajouter `ex_inscriptions` à `AgPacha`, sur `hadrlab1`. Lisez l'erreur.
3. Faites ce qu'il faut pour que la base puisse entrer dans le groupe, puis ajoutez-la.
4. Attendez que les copies soient créées et à jour sur les deux secondaires, en lisant l'état
   sur le primaire, pas en comptant les secondes.
5. Lancez `check.sh`. Il sort en 0 quand tout tient.

`check.sh` vérifie, sur `hadrlab1`, que `AgPacha` existe et que `hadrlab1` en est le primaire,
que `ex_inscriptions` est une base du groupe, que le seeding automatique vers `hadrlab2` et vers
`hadrlab3` s'est terminé, et que `hadrlab2` est `SYNCHRONIZED` et `hadrlab3` `SYNCHRONIZING` ou
`SYNCHRONIZED`. Sur `hadrlab2` et `hadrlab3`, il vérifie que la copie locale existe et qu'elle
est jointe au groupe.

## À réfléchir

- Le message de l'étape 2 conseille une commande. Pourquoi échoue-t-elle ?
- Vous n'avez rien eu à faire sur les secondaires. Quelle instruction, jouée à la jonction, vous
  en a dispensé ?
- `hadrlab3` reste `SYNCHRONIZING`. Comment sauriez-vous s'il est en retard ?

