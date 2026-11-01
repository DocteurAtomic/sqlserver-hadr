# Démonstrations du module 7

Elles se jouent sur le cluster Windows du formateur (deux nœuds, `SQL01` et `SQL02`, un
contrôleur de domaine `DC01`, le groupe de disponibilité `Pacha`), dans un PowerShell lancé en
administrateur sur un nœud, et non sur les conteneurs du labo. Vous les suivez en vidéo ; leurs
sorties réelles sont dans `data/cluster/`, que l'exercice lit. `setup/run-scripts.sh` ne lance
que `00-setup.sh` et `99-cleanup.sh`, qui ne touchent pas aux conteneurs : les autres fichiers
sont en `.ps1`, ou portent `ci: skip`.

| Script | Où | Clip |
|---|---|---|
| `01-cluster-tour.ps1` | `SQL01` | 7.1 : nœuds, réseau, rôles, ressources et dépendances |
| `02-cluster-from-sql.sql` | `SQL01`, dans `sqlcmd` | 7.1 et 7.2 : le cluster vu de SQL Server |
| `03-quorum.ps1` | `SQL01` | 7.2 : type de quorum, témoin, votes |
| `04-watch.ps1` | le nœud qui reste | 7.2 et 7.3 : la surveillance pendant une panne |
| `05-cluster-log.ps1` | le nœud qui reste | 7.3 : journal du cluster et journal d'erreurs |
| `06-witness.ps1` | `DC01`, puis `SQL01` | 7.3 : le témoin de partage de fichiers, et son retrait |

Les pannes se provoquent depuis l'hyperviseur, pendant que `04-watch.ps1` tourne sur l'autre
nœud : coupure franche par `virsh destroy SQL02` (avec Hyper-V : `Stop-VM SQL02 -TurnOff`),
arrêt propre par `Stop-Computer -Force` dans `SQL02`, retour par `virsh start SQL02`. Après une
bascule, `SQL01` redevient primaire par `ALTER AVAILABILITY GROUP Pacha FAILOVER;` lancé sur
`SQL01` une fois ses bases `SYNCHRONIZED`. `/forcequorum` n'est jamais lancé : le clip 7.3 en
parle sans le jouer.

---

# Module 7 demos

They run on the trainer's Windows cluster, in an elevated PowerShell on a node, not on the
containers; their real outputs are in `data/cluster/`, which the exercise reads.
`setup/run-scripts.sh` runs only `00-setup.sh` and `99-cleanup.sh`, which leave the containers
alone.
