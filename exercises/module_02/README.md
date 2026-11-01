# Exercice du module 2

Objectif : monter un log shipping de la base `ex_logship` de `hadrlab1` vers `hadrlab3`, voir
une ligne arriver sur le secondaire, puis basculer vers `hadrlab3` sans perdre une ligne.

L'exercice crée sa base, `ex_logship`, et n'écrit rien d'autre sur le labo.
`demos/module_02/99-cleanup.sh` la supprime à la fin du module, avec ses travaux et ses
fichiers.

## Les fichiers

- `1-start.sh` crée `ex_logship` sur `hadrlab1`, en mode de récupération complet, sans aucune
  sauvegarde : une table `dbo.Registration` de 100 lignes (`label`, `written_at`). Il crée aussi
  deux dossiers vides sur le volume partagé : `/var/opt/mssql/share/ex_logship` pour la
  sauvegarde complète, `/var/opt/mssql/share/logship/ex_logship` pour les sauvegardes du
  journal. Le relancer défait une tentative précédente (log shipping, travaux, bases,
  fichiers) et repart de zéro.
- `check.sh` lit l'état des deux instances et dit ce qui manque.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. D'autres réponses sont
  justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_02/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_02/1-start.sh
./exercises/module_02/check.sh         # avec Podman : ENGINE=podman ./exercises/module_02/check.sh
```

## La consigne

1. Prenez une sauvegarde complète de `ex_logship` dans `/var/opt/mssql/share/ex_logship`,
   et restaurez-la sur `hadrlab3` `WITH NORECOVERY`.
2. Faites de `hadrlab1` le primaire : sauvegardes du journal dans
   `/var/opt/mssql/share/logship/ex_logship`, un travail planifié, `hadrlab3` déclaré comme
   secondaire.
3. Faites de `hadrlab3` le secondaire : copie vers un dossier de `hadrlab3`
   (`/var/opt/mssql/logship-copy/ex_logship`, par exemple), restauration en `STANDBY`, deux
   travaux planifiés.
4. Sur `hadrlab1`, insérez une ligne dont le `label` vaut `probe`. Attendez qu'elle soit
   lisible sur `hadrlab3`, ou lancez les trois travaux dans l'ordre (`msdb.dbo.sp_start_job`,
   en attendant la fin de chacun).
5. Basculez vers `hadrlab3` sans perte : désactivez le travail de sauvegarde, copiez et
   restaurez ce qui reste, désactivez la copie et la restauration, sauvegardez la fin du
   journal de `hadrlab1` `WITH NORECOVERY` et restaurez-la sur `hadrlab3` `WITH RECOVERY`.
6. Sur `hadrlab3`, insérez une ligne dont le `label` vaut `after failover`.
7. Lancez `check.sh`. Il sort en 0 quand tout tient, en 1 sinon.

`check.sh` vérifie, sur `hadrlab1`, que `ex_logship` est un primaire de log shipping dont
`hadrlab3` est le secondaire, que son travail de sauvegarde existe et est désactivé, et que la
base est `RESTORING`. Sur `hadrlab3`, il vérifie la configuration du secondaire en `STANDBY`,
ses deux travaux désactivés, la ligne `probe`, une sauvegarde du journal prise après elle et
restaurée en `STANDBY`, la surveillance qui a vu une restauration, la base en ligne et
modifiable, la dernière sauvegarde du journal de `hadrlab1` restaurée jusqu'au même LSN, et
la ligne `after failover`.

## À réfléchir

- Le travail de copie et le travail de restauration ont la même planification que la
  sauvegarde. Combien de temps une ligne met-elle à arriver, au pire ? Et si on les décale ?
- Entre l'étape 4 et l'étape 5, `hadrlab1` disparaît. Combien de lignes perdez-vous, et
  comment le savoir en lisant `hadrlab3` ?
- Après la bascule, que faut-il pour que `hadrlab1` redevienne le primaire, sans nouvelle
  sauvegarde complète ?
