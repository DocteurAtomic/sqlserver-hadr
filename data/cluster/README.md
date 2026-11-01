# Sorties du cluster Windows du cours

Relevées le 1er novembre 2026 sur le cluster du formateur : deux nœuds, `SQL01` et `SQL02`
(Windows Server 2019, SQL Server 2025 CU9), un contrôleur de domaine `DC01` qui n'est pas un
nœud, le groupe de disponibilité `Pacha` en validation synchrone et basculement automatique.
Les trois machines virtuelles tournent sur le même hôte. Chaque fichier est la sortie d'une
commande lancée sur un nœud ; seuls les retours chariot, les espaces de fin de ligne et les
lignes vides en double ont été retirés, et les journaux réduits aux lignes qui racontent la
panne.

| Dossier | Ce qu'il montre | Lu sur |
|---|---|---|
| `start/` | le cluster sain, sans témoin | `SQL01` |
| `sql02-shut-down/` | `SQL02` arrêté proprement | `SQL01` |
| `sql02-power-loss/` | `SQL02` coupé net, sans témoin | `SQL01` |
| `sql01-power-loss/` | `SQL01` coupé net, sans témoin | `SQL02` |
| `with-witness/` | le cluster avec un témoin de partage de fichiers sur `DC01` | `SQL01` |
| `with-witness-sql02-power-loss/` | `SQL02` coupé net, avec le témoin | `SQL01` |

Dans chaque dossier, quand la commande a pu répondre :

- `cluster.txt` : `Get-Cluster` (quorum dynamique, vote du témoin, pulsations) ;
- `quorum.txt` : `Get-ClusterQuorum` (`QuorumResource` vide : pas de témoin) ;
- `nodes.txt` : `Get-ClusterNode`, avec `NodeWeight` (le vote attribué) et `DynamicWeight` (le
  vote que le quorum dynamique laisse au nœud à cet instant) ;
- `groups.txt` : `Get-ClusterGroup` et `Get-ClusterResource` ;
- `sql.txt` : `sys.dm_hadr_cluster_members`, `sys.dm_hadr_cluster` et l'état des réplicas ;
- `watch-<nœud>.txt` : la surveillance de `demos/module_07/04-watch.ps1` pendant la panne, une
  ligne à chaque changement ;
- `cluster-log-<nœud>.txt` et `errorlog-<nœud>.txt` : les lignes du journal du cluster (heure
  UTC) et du journal d'erreurs de SQL Server (heure locale du serveur, UTC moins 8 heures).

`events.txt` donne l'heure UTC de chaque coupure, arrêt et redémarrage. Sans quorum, un nœud
ne répond plus aux commandes du cluster : `sql02-power-loss/` n'a donc ni `nodes.txt` ni
`quorum.txt`, et sa surveillance dit pourquoi. `sql02-shut-down/sql.txt` a été relevé avant
l'ajout de la colonne `number_of_current_votes`. Le propriétaire du groupe du cluster change à
chaque défaillance : `SQL02` dans les vidéos, `SQL01` dans `start/`.

---

# Outputs of the course's Windows cluster

Command outputs read on the nodes of the trainer's two-node cluster on 2026-11-01, one folder
per state. `events.txt` gives the UTC time of each power off, shutdown and power on. Cluster
logs are in UTC, SQL Server error logs in the server's local time (UTC minus 8 hours).
