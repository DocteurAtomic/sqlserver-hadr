# Démonstrations du module 10

Les clips 10.1 à 10.3 se jouent sur les conteneurs du labo, le clip 10.4 sur le cluster Windows
du formateur, que vous suivez en vidéo.

## Sur les conteneurs

`00-setup.sh` crée `m10_registration` (`dbo.Registration`, `dbo.Contact` de 200 000 lignes,
`dbo.Visit` d'un million de lignes) et `m10_archive`, puis recrée `AgPacha` avec la première, en
une trentaine de secondes. `99-cleanup.sh` retire les groupes et remet le labo dans son état
d'installation.

| Script | Clip | Ce qu'il montre |
|---|---|---|
| `01-database.sh` | 10.1 | ajouter `m10_archive`, la retirer, la remettre sans nouveau seeding |
| `02-replica.sh` | 10.1 | retirer `hadrlab3`, ce que l'instance garde, le rajouter |
| `03-online-rebuild.sh` | 10.2 | la reconstruction en ligne qui fige une partie des écritures, puis `WAIT_AT_LOW_PRIORITY` |
| `04-resumable.sh` | 10.2 | la reconstruction reprenable, mise en pause, le journal libéré, la reprise |
| `05-secondary.sh` | 10.3 | le journal d'une reconstruction vu des secondaires, le rejeu bloqué par une lecture |

`04-resumable.sh` est marqué `ci: skip` : sa reprise prend de 7 à 13 minutes sur le labo, la cause
n'est pas établie (une reconstruction reprenable sans pause prend 6 secondes).

```bash
ENGINE=podman ./demos/module_10/00-setup.sh
ENGINE=podman ./demos/module_10/01-database.sh
```

## Sur le cluster Windows (clip 10.4)

Le cluster : `SQL01`, `SQL02`, le contrôleur de domaine `DC01`, le groupe `Pacha` et son
listener `PachaSQL`. Tous ces fichiers sont marqués `ci: skip`.

| Script | Où | Rôle |
|---|---|---|
| `00-setup-cluster.sql` | `SQL01` | crée `m10_rolling` et l'ajoute à `Pacha` |
| `10-rolling-state.sql` | l'un ou l'autre nœud | la version, les réplicas, leur mode de bascule, l'état des copies |
| `11-failover-mode.sql` | le primaire | `sqlcmd -v MODE=MANUAL`, puis `MODE=AUTOMATIC` |
| `12-watch.sql` | le primaire | une ligne à chaque changement d'état pendant la mise à jour du secondaire, `sqlcmd -v SECONDS=900` |
| `13-update-node.ps1` | le nœud à mettre à jour, secondaire | téléchargement, contrôle du SHA-256, setup ; `-RestartOnly` pour une répétition |
| `demos/module_08/03-failover-here.sql` | le nœud qui devient primaire | la bascule planifiée |
| `demos/module_08/02-client.ps1 -Database m10_rolling` | `DC01` | un `INSERT` par le listener toutes les demi-secondes |
| `99-cleanup-cluster.sql` | `SQL01` | remet la bascule automatique, retire et supprime `m10_rolling` ; puis `DROP DATABASE m10_rolling;` sur `SQL02` |

L'ordre : `11` en `MANUAL`, `13` sur `SQL02` pendant que `12` tourne sur `SQL01`, bascule vers
`SQL02`, `13` sur `SQL01`, bascule vers `SQL01`, `11` en `AUTOMATIC`.

---

# Module 10 demos

Clips 10.1 to 10.3 run on the lab containers, clip 10.4 on the trainer's Windows cluster, which
you follow on video. `00-setup.sh` creates `m10_registration` and `m10_archive` and recreates
`AgPacha` with the first; `99-cleanup.sh` puts the lab back in its installed state.
`04-resumable.sh` is `ci: skip`: its resume takes 7 to 13 minutes on the lab, for a reason not
established. On the cluster: `00-setup-cluster.sql` on `SQL01`; `11-failover-mode.sql` with
`MODE=MANUAL`; `13-update-node.ps1` on `SQL02` while `12-watch.sql` runs on `SQL01`; failover
to `SQL02` with `demos/module_08/03-failover-here.sql`; `13-update-node.ps1` on `SQL01`;
failover back; `MODE=AUTOMATIC`; `99-cleanup-cluster.sql` on `SQL01`, then
`DROP DATABASE m10_rolling;` on `SQL02`. The client is `demos/module_08/02-client.ps1 -Database
m10_rolling` on `DC01`.
