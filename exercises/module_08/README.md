# Exercice du module 8

Objectif : diagnostiquer un groupe de disponibilité dont deux copies se sont arrêtées, écrire le
rapport de ce diagnostic, puis réparer.

L'exercice crée sa base, `ex_repair`, et son groupe, `AgRepair`, sans cluster : `hadrlab1`
primaire, `hadrlab2` en validation synchrone, `hadrlab3` en asynchrone. Il ne touche pas au
groupe `AgPacha` des démonstrations. `demos/module_08/99-cleanup.sh` retire le groupe et
supprime la base à la fin du module.

## Les fichiers

- `1-start.sh` retire les restes d'un essai précédent (le groupe `AgRepair`, `ex_repair` et son
  historique sur les trois instances, le dossier `ex_archive`), crée `ex_repair` sur `hadrlab1`
  avec sa sauvegarde complète, crée `AgRepair` par `setup/ag-create.sh`, puis fait sur le
  primaire une modification qui casse les deux secondaires, et écrit 200 lignes. Il ne dit pas
  ce qui a cassé. Il écrit aussi `report.md`, le rapport à remplir, ignoré par git.
- `check.sh` lit l'état du groupe sur `hadrlab1` et sur chaque secondaire, et dit ce qui ne va
  pas.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché : il répare et écrit un
  rapport rempli. D'autres réparations sont justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_08/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_08/1-start.sh
./exercises/module_08/check.sh         # avec Podman : ENGINE=podman ./exercises/module_08/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui ne va pas.
2. Sur `hadrlab1`, lisez l'état des copies de `ex_repair` dans
   `sys.dm_hadr_database_replica_states` : état de synchronisation, `is_suspended`,
   `suspend_reason_desc`. Qui a suspendu ces copies ?
3. Lisez le journal d'erreurs de chaque secondaire (`EXEC sp_readerrorlog;`). Notez l'heure,
   l'erreur et le fichier en cause.
4. Remplissez les quatre premières lignes de `report.md`.
5. Réparez : la cause d'abord, puis la reprise des copies. Notez chaque geste dans le rapport,
   dans l'ordre, avec l'instance où vous l'avez fait. Pour agir dans un conteneur en
   administrateur : `docker exec -u 0 hadrlab2 ...` (ou `podman exec -u 0 ...`).
6. Lancez `check.sh` : il sort en 0 quand les deux copies sont synchronisées, sans retard
   d'envoi, et que chaque secondaire a la base et son nouveau fichier en ligne.

## À réfléchir

- Une reprise envoyée sur le primaire change-t-elle quelque chose ?
- Que se passe-t-il si vous reprenez les copies avant d'avoir corrigé la cause ?
- Pendant la suspension, le primaire continue d'écrire. Que devient son journal ?

---

# Module 8 exercise

Goal: diagnose an availability group whose two secondary copies stopped, write the report of
the diagnosis, then repair it.

`1-start.sh` builds the database `ex_repair` and the group `AgRepair` (no cluster; `hadrlab2`
synchronous, `hadrlab3` asynchronous), then makes on the primary a change that breaks both
secondaries, and writes `report.md`, the report to fill in (ignored by git). Read the state of
the copies on `hadrlab1`, the error log of each secondary, write the cause in the report, fix
the cause, resume the copies, and run `check.sh` until it exits with 0. `solution/2-solution.sh`
is one solution. `AgPacha` is not touched; `demos/module_08/99-cleanup.sh` removes everything at
the end of the module.
