# Exercice du module 10

Objectif : remettre en état un groupe de disponibilité après un incident. Une copie a été
suspendue et le journal s'accumule pour elle ; reprenez-la. Puis retirez un réplica du groupe et
rajoutez-le, comme on le fait avant de reconstruire un serveur, et laissez un groupe à trois
réplicas, aucune copie suspendue ni en retard.

L'exercice crée sa base, `ex_operations`, et son groupe, `AgOps`, sur les trois instances
(`hadrlab1` primaire, `hadrlab2` synchrone, `hadrlab3` asynchrone). Il ne touche pas au groupe
`AgPacha` des démonstrations. `demos/module_10/99-cleanup.sh` retire le groupe et supprime la
base à la fin du module.

## Les fichiers

- `1-start.sh` retire ce qu'un essai précédent a laissé, crée `ex_operations` sur `hadrlab1`
  avec sa sauvegarde complète, puis `AgOps`. Il note dans `ex_operations.dbo.StartState`
  l'identifiant que le groupe a donné au réplica de `hadrlab3`, suspend la copie de `hadrlab2`,
  puis écrit 500 lignes sur `hadrlab1`.
- `check.sh` lit l'état du groupe sur `hadrlab1` et sur `hadrlab3`, et dit ce qui manque.
- `solution/` contient un corrigé, à lire après avoir cherché : `1-resume.sql` puis
  `2-replica.sh`. `check.sh` lit l'état du groupe et ignore les commandes : d'autres réponses sont justes.

```bash
./exercises/module_10/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_10/1-start.sh
./exercises/module_10/check.sh         # avec Podman : ENGINE=podman ./exercises/module_10/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Sur `hadrlab1`, trouvez la copie suspendue et la raison de sa suspension
   (`sys.dm_hadr_database_replica_states`). Que dit `log_reuse_wait_desc` pour `ex_operations`
   dans `sys.databases` ?
3. Reprenez la copie, sur l'instance où elle a été suspendue, et attendez qu'elle soit
   `SYNCHRONIZED`.
4. Retirez `hadrlab3` de `AgOps`. Lisez le groupe sur `hadrlab1`, puis sur `hadrlab3`, tout de
   suite et une trentaine de secondes plus tard.
5. Rajoutez `hadrlab3` au groupe, en validation asynchrone, seeding automatique. Si le `JOIN`
   est refusé, lisez le message : il dit quoi faire. Un groupe qu'on vient de supprimer peut
   mettre quelques secondes à quitter l'instance (Msg 41180) : recommencez alors le `JOIN`.
6. Lancez `check.sh`. Il sort en 0 quand tout tient.

`check.sh` vérifie que `AgOps` est sur les trois instances avec `hadrlab1` primaire ; que le
réplica de `hadrlab3` n'est plus celui que `1-start.sh` a créé (son identifiant a changé, il a
donc été retiré puis rajouté) ; que `hadrlab3` n'a qu'un `AgOps`, connecté ; et que chaque copie,
lue sur `hadrlab1`, est à jour (`SYNCHRONIZED` pour `hadrlab2`, `SYNCHRONIZING` ou
`SYNCHRONIZED` pour `hadrlab3`) et non suspendue.

## À réfléchir

- La copie de `hadrlab3` a-t-elle été recopiée par un nouveau seeding ? Regardez sur
  `hadrlab1` les sauvegardes de `ex_operations` vers un périphérique nommé par un GUID dans
  `msdb.dbo.backupset`.
- Combien de temps le journal de `ex_operations` serait-il retenu sur `hadrlab1` si personne
  ne reprenait la copie suspendue ?
- Sous un cluster Windows, le réplica retiré se comporte-t-il de la même façon ? Learn décrit
  un autre comportement ; le cours ne l'a pas mesuré.
