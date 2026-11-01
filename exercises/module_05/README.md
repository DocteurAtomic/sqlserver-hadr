# Exercice du module 5

Objectif : faire de `hadrlab3` le serveur des sauvegardes et des rapports. La direction veut
les sauvegardes sur `hadrlab3`, jamais sur `hadrlab2`, qu'elle garde pour la bascule ; elle
veut une chaîne de restauration éprouvée, et l'équipe des rapports veut lire sur `hadrlab3`
sans risquer d'y écrire.

L'exercice crée sa base, `ex_backup`, l'ajoute au groupe `AgPacha`, et restaure sa chaîne
sous le nom `ex_backup_verif`. Il change aussi des réglages du groupe, que
`demos/module_05/99-cleanup.sh` efface en retirant le groupe à la fin du module.

## Les fichiers

- `1-start.sh` vérifie que le groupe `AgPacha` existe, et le crée avec `PachadataTraining` s'il
  manque (`setup/ag-create.sh`). Il remet les réglages que l'exercice demande de changer :
  préférence de sauvegarde `SECONDARY`, priorité 50 sur les trois réplicas, `hadrlab3` en
  validation asynchrone et fermé à la lecture (`ALLOW_CONNECTIONS = NO`). Il crée ensuite
  `ex_backup` sur `hadrlab1`, avec `dbo.Invoice` (1 000 factures) et `dbo.AddInvoice`, qui
  écrit une facture de plus, la sauvegarde, l'ajoute au groupe et attend que les copies soient à
  jour. Le relancer supprime `ex_backup` et `ex_backup_verif` et repart de zéro.
- `check.sh` lit l'état des trois instances et dit ce qui manque.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. D'autres réponses sont
  justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_05/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_05/1-start.sh
./exercises/module_05/check.sh         # avec Podman : ENGINE=podman ./exercises/module_05/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Réglez le groupe pour que `sys.fn_hadr_backup_is_preferred_replica('ex_backup')` réponde 1
   sur `hadrlab3` et 0 sur `hadrlab1` et `hadrlab2`, avec une préférence qui tient les
   sauvegardes hors du primaire. Lisez la réponse de la fonction sur les trois instances
   après chaque changement : le clip 5.3 montre ce qu'elle exige d'un secondaire.
3. Sur `hadrlab3`, sans `COPY_ONLY`, dans `/var/opt/mssql/share/ex_backup/` : une sauvegarde
   complète, puis une différentielle, puis une sauvegarde du journal. Lancez
   `EXEC ex_backup.dbo.AddInvoice;` sur `hadrlab1` après la complète et après la
   différentielle. Avant la différentielle, vérifiez que `hadrlab3` connaît sa complète comme
   base différentielle ; avant chaque sauvegarde, vérifiez qu'il a rejoué la dernière facture.
4. Sur `hadrlab1`, restaurez la chaîne sous le nom `ex_backup_verif` (`WITH MOVE` pour les deux
   fichiers), jusqu'à une base en ligne qui contient les deux factures ajoutées.
5. Ouvrez `hadrlab3` aux seules connexions qui déclarent une intention de lecture, et
   vérifiez-le depuis le `sqlcmd` d'un conteneur, dans le réseau du labo :
   `docker exec -it hadrlab1 /opt/mssql-tools18/bin/sqlcmd -C -S hadrlab3 -U sa -d ex_backup -K ReadOnly`.
6. Lancez `check.sh`. Il sort en 0 quand tout tient.

`check.sh` vérifie, sur `hadrlab1`, que `ex_backup` est une base du groupe et que la préférence
vaut `SECONDARY` ou `SECONDARY_ONLY` ; sur chaque instance, la réponse de la fonction ; dans le
`msdb` de `hadrlab3`, une complète sans `COPY_ONLY`, une différentielle et une sauvegarde du
journal de `ex_backup` prises là ; sur `hadrlab1`, que `ex_backup_verif` est en ligne, restaurée
depuis une complète, une différentielle et un journal pris sur `hadrlab3`, avec au moins
1 002 factures ; et depuis le conteneur `hadrlab1`, qu'une connexion à `hadrlab3` avec
`-K ReadOnly` arrive sur `hadrlab3` en `READ_ONLY`, et que la même sans intention est refusée.

## À réfléchir

- Ce que vous avez dû changer pour que la fonction désigne `hadrlab3` a un prix, mesuré au
  module 4 : lequel ? Un travail de sauvegarde qui teste le rôle du réplica au lieu de la
  fonction l'éviterait-il, et que perdrait-il ?
- Si la différentielle refuse de se restaurer (Msg 3136), sur quelle complète repose-t-elle ?
  `differential_base_lsn` dans `msdb.dbo.backupset` le dit.
- Le corrigé ajoute le résultat à `evidence/module_05.md`.
