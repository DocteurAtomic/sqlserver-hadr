# Démonstrations du module 8

Elles se jouent sur le cluster Windows du formateur (deux nœuds, `SQL01` et `SQL02`, un
contrôleur de domaine `DC01`, le groupe de disponibilité `Pacha` et son listener `PachaSQL`), et
non sur les conteneurs du labo : vous les suivez en vidéo. Elles mesurent sur une base du
module, `m08_registrations`, ajoutée à `Pacha` le temps du module, sur un petit disque `M:` de
chaque nœud. `setup/run-scripts.sh` ne lance que `00-setup.sh` et `99-cleanup.sh`, qui ne font
rien de plus que nettoyer l'exercice sur les conteneurs : les autres fichiers sont en `.ps1`, ou
portent `ci: skip`.

## Préparer le cluster

1. Sur `SQL01`, dans un PowerShell administrateur : `.\00-setup-cluster.ps1 -SizeMB 300` ; sur
   `SQL02` : `.\00-setup-cluster.ps1 -SizeMB 100`. Le disque plus petit de `SQL02` se remplit le
   premier au clip 8.4.
2. Sur `SQL02`, dans `sqlcmd` : `ALTER AVAILABILITY GROUP Pacha GRANT CREATE ANY DATABASE;`
   (le réplica de `SQL02` crée sa copie lui-même, en seeding automatique).
3. Sur `SQL01`, dans `sqlcmd` : `00-setup-cluster.sql`.

## Les scripts

| Script | Où | Clip |
|---|---|---|
| `01-listener.ps1` | `SQL01` | 8.1 : les ressources du listener, le DNS, l'écoute de l'instance |
| `02-client.ps1` | `DC01` | 8.1 à 8.3 : un client qui écrit par le listener toutes les demi-secondes |
| `03-failover-here.sql` | le nœud qui devient primaire | 8.1 et 8.2 : bascule planifiée, après contrôle de `SYNCHRONIZED` |
| `demos/module_07/04-watch.ps1` | le nœud qui reste | 8.2 : la surveillance du module 7, reprise telle quelle |
| `05-failover-log.ps1` | chaque nœud, en local | 8.2 : les lignes du journal du cluster sur la panne et la bascule |
| `06-health.sql`, `06-lease.ps1` | `SQL01` | 8.3 : la politique de bascule, la session de la DLL, le bail |
| `07-db-state.sql` | l'un ou l'autre nœud | 8.3 et 8.4 : l'état de chaque base et de chaque copie |
| `08-disk.ps1` | le nœud dont le disque disparaît | 8.3 : `M:` hors ligne et en ligne |
| `09-writer.ps1` | `SQL01` | 8.4 : un `INSERT` numéroté toutes les demi-secondes, en local |
| `10-freeze.ps1` | `SQL02` | 8.4 : le processus `sqlservr` gelé, puis dégelé |
| `11-fill.sql` | `SQL01` | 8.4 : remplir `M:` lot par lot |

Il n'y a pas de `04` dans ce dossier : la surveillance est celle du module 7.

Le clip 8.2 arrête le service par `Stop-Service MSSQLSERVER -Force` sur `SQL01`. Si le cluster
refuse la bascule (`Not failing over group Pacha` dans le journal), le seuil de défaillances du
rôle est atteint : la vidéo relève ce seuil à 10 par `(Get-ClusterGroup Pacha).FailoverThreshold
= 10`, et `99-cleanup-cluster.ps1` le remet à sa valeur par défaut. Le clip 8.4 agrandit le disque
plein de `SQL02` depuis l'hyperviseur, puis lance `ALTER DATABASE m08_registrations SET HADR
RESUME` sur `SQL02`. Après chaque bascule, `SQL01` redevient primaire par
`03-failover-here.sql`.

## Remettre le cluster en état

1. Sur `SQL01`, dans `sqlcmd` : `99-cleanup-cluster.sql`, qui retire la base du groupe et la
   supprime des deux nœuds.
2. Sur chaque nœud : `.\99-cleanup-cluster.ps1`, qui remet le seuil du rôle, détache le disque
   et supprime `C:\m08`.

---

# Module 8 demos

They run on the trainer's Windows cluster (nodes `SQL01` and `SQL02`, domain controller `DC01`,
availability group `Pacha` with its listener `PachaSQL`), not on the containers. They measure on
a database of the module, `m08_registrations`, added to `Pacha` for the module, on a small disk
`M:` on each node. `setup/run-scripts.sh` runs only `00-setup.sh` and `99-cleanup.sh`, which only
clean the exercise up on the containers.

Setup: `00-setup-cluster.ps1 -SizeMB 300` on `SQL01` and `-SizeMB 100` on `SQL02`, then
`ALTER AVAILABILITY GROUP Pacha GRANT CREATE ANY DATABASE;` on `SQL02`, then
`00-setup-cluster.sql` on `SQL01`. Cleanup: `99-cleanup-cluster.sql` on `SQL01`, then
`99-cleanup-cluster.ps1` on each node. The watch window is `demos/module_07/04-watch.ps1`. The
table above gives, for each script, the node it runs on and the clip that uses it.
