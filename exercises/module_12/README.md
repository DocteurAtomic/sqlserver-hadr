# Exercice du module 12

Objectif : diagnostiquer un groupe de disponibilité malade avec les outils du module (la
requête de santé, la session `AlwaysOn_health`, le journal des erreurs), trouver la cause, et
réparer.

L'exercice crée sa base, `ex_health`, et son groupe, `AgHealth`, sans cluster : `hadrlab1`
primaire, `hadrlab2` en validation synchrone, `hadrlab3` en asynchrone. Il ne touche pas aux
groupes des démonstrations ni aux points de terminaison des instances.
`demos/module_12/99-cleanup.sh` retire le groupe et supprime la base à la fin du module.

## Les fichiers

- `1-start.sh` retire les restes d'un essai précédent, crée `ex_health` sur `hadrlab1` avec sa
  sauvegarde complète, crée `AgHealth` par `setup/ag-create.sh`, démarre la session
  `AlwaysOn_health` sur les trois instances si elle ne tourne pas, puis fait sur le primaire
  une modification de la configuration du groupe qui coupe un réplica de `AgHealth`, et de lui
  seul. Il écrit ensuite 2 000 lignes. Il ne dit pas ce qu'il a changé.
- `check.sh` lit l'état du groupe sur `hadrlab1` et dit ce qui ne va pas.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché : il dit le diagnostic
  dans ses commentaires, puis répare. `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_12/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_12/1-start.sh
./exercises/module_12/check.sh         # avec Podman : ENGINE=podman ./exercises/module_12/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui ne va pas.
2. Sur `hadrlab1`, lancez la requête de santé du module (`setup/ag-health.sql`). Que valent la
   file d'envoi et la perte estimée pour le réplica malade ? Quel RPO pouvez-vous annoncer pour
   lui ?
3. Le même réplica est-il malade dans les autres groupes de l'instance ? Qu'en concluez-vous
   sur son point de terminaison ?
4. Lisez ce que `AlwaysOn_health` a enregistré sur `hadrlab1` depuis le lancement de
   `1-start.sh` (`demos/module_12/05-read-health.sh 5` le fait). Quelle adresse le primaire
   essaie-t-il de joindre ? Quelle instruction l'a réglée ?
5. Réparez la cause, sur l'instance qui convient. Le primaire retente la connexion de lui-même :
   comptez jusqu'à une demi-minute.
6. Lancez `check.sh` : il sort en 0 quand le groupe est `HEALTHY`, les deux secondaires
   connectés, leurs copies de `ex_health` à jour et leur file d'envoi connue.

## À réfléchir

- L'arbre de décision du support dit, pour un réplica déconnecté : redémarrer le point de
  terminaison. Que donne-t-il ici ? Et qu'aurait-il coûté aux autres groupes ?
- Pendant la panne, le primaire continue d'écrire. Que devient son journal pour `ex_health` ?
- Si `AlwaysOn_health` n'avait pas tourné, où auriez-vous trouvé l'adresse fautive ?

---

# Module 12 exercise

Goal: diagnose a sick availability group with the tools of the module (the health query, the
`AlwaysOn_health` session, the error log), find the cause, and repair it.

`1-start.sh` builds the database `ex_health` and the group `AgHealth` (no cluster; `hadrlab2`
synchronous, `hadrlab3` asynchronous), starts `AlwaysOn_health` on the three instances if it
does not run, then makes on the primary a change of the group's configuration that cuts one
replica off `AgHealth` alone, and writes 2,000 rows. Read the health of the group on `hadrlab1`
(`setup/ag-health.sql`), what `AlwaysOn_health` recorded (`demos/module_12/05-read-health.sh`),
fix the cause, and run `check.sh` until it exits with 0. `solution/2-solution.sh` is one
solution. The endpoints and the groups of the demos are not touched;
`demos/module_12/99-cleanup.sh` removes everything at the end of the module.
