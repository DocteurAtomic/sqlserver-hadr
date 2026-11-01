# Le labo Pacemaker (facultatif)

Labo du module 13, « Linux et Pacemaker ». Il est facultatif : le reste du cours ne s'en
sert pas, et l'intégration continue du dépôt ne le joue pas. Il demande Podman sous Linux,
x86-64 : les nœuds font tourner systemd comme premier processus (`podman run
--systemd=always`), ce que Docker Desktop, WSL et macOS ne font pas de la même façon. Il n'a
été essayé que sous Podman 5.8.9 sans root, sur Fedora.

Trois nœuds Ubuntu 24.04 sur un réseau à eux, `hadr-pcs` (10.89.50.0/24, adresses fixes) :

| Nœud | Adresse | Édition | Rôle dans `AgPcs` |
|---|---|---|---|
| `pc1` | 10.89.50.11 | Developer | réplica synchrone, primaire au départ |
| `pc2` | 10.89.50.12 | Developer | réplica synchrone |
| `pc3` | 10.89.50.13 | Express | réplica de configuration seule |
| | 10.89.50.20 | | adresse virtuelle (ressource `IPaddr2`) et listener `agpcs` |

Les versions, fixées par le `Containerfile` : SQL Server 2025 CU7 (17.0.4065.4, la version
des conteneurs du cours) et `mssql-server-ha` de la même version, dont l'agent de ressource
`ocf:mssql:ag` (v1, celui que Microsoft prend en charge en production ; l'agent v2,
`ocf:mssql:agv2`, est en préversion depuis le CU3). Pacemaker 2.1.6, Corosync 3.1.7 et
`pcs` 0.11.7 viennent d'Ubuntu 24.04, que SQL Server 2025 prend en charge depuis son CU1.
SQL Server 2025 tourne sous Red Hat Enterprise Linux 9 et 10 et sous Ubuntu 22.04 et 24.04 ;
SUSE n'est plus pris en charge depuis 2025.

Il faut environ 6 Go de mémoire libre (2 Go par nœud) : arrêtez d'abord le labo du cours,
les noms et les adresses ne se gênent pas mais la mémoire si.

    ENGINE=podman ./setup/stop.sh       # le labo du cours, hadrlab1 à hadrlab3
    ./extra/pacemaker/all.sh            # le labo Pacemaker, de zéro

`all.sh` enchaîne quatre scripts, qu'on peut aussi lancer un par un :

1. `lab.sh` construit l'image `hadr-pcs:2025` si elle manque (environ deux minutes la
   première fois : paquets d'Ubuntu et 300 Mo de SQL Server), démarre les trois nœuds,
   installe SQL Server sur chacun (`mssql-conf setup`), active la haute disponibilité et
   limite chaque instance à 2 Go ;
2. `endpoints.sh` crée les points de terminaison par certificat et échange les certificats ;
3. `ag.sh` crée sur `pc1` la base `m13_registration` et le groupe `AgPcs` en
   `CLUSTER_TYPE = EXTERNAL`, et y joint `pc2` et `pc3` ;
4. `pacemaker.sh` crée le login de l'agent, le cluster `hadrpcs`, les ressources
   `ag_cluster` et `virtualip` et leurs contraintes, puis le listener `agpcs`.

Mesuré le 1er novembre 2026, image déjà construite : 96 secondes jusqu'au cluster sain.
`status.sh` montre l'état des deux côtés, cluster et SQL Server ; `writer.sh` écrit une ligne
toutes les demi-secondes par l'adresse virtuelle, pour voir une bascule du côté d'un client.

Mots de passe de labo, écrits en clair dans `lib.sh` : `sa` et `Hadr-2026!lab` comme pour le
labo du cours, `hacluster` et `Pcs-2026!lab`, `pacemakerLogin` et `Pacemaker-2026!lab`. Une
instance s'interroge depuis son nœud :

    podman exec -it pc1 /opt/mssql-tools18/bin/sqlcmd -C -S 127.0.0.1 -U sa
    podman exec -it pc1 pcs status

## Les démonstrations et l'exercice

`demos/` contient les scènes du module, dans l'ordre des vidéos, chacune rendant le labo
avec `pc1` primaire : `01-cluster.sh` (le groupe vu par le cluster et par SQL Server),
`02-planned-move.sh` (la bascule planifiée par `pcs resource move`), `03-primary-killed.sh`
(le nœud du primaire tué), `04-sql-stopped.sh` (SQL Server arrêté sur le primaire),
`05-quorum-lost.sh` (deux nœuds sur trois perdus). `exercise/` contient l'exercice : son
énoncé est dans `exercise/README.md`.

## Les écarts avec une installation réelle

- Pas de fencing (`stonith-enabled=false`) : rien à piloter dans des conteneurs. Microsoft
  ne prend pas en charge un cluster de production sans fencing.
- `--security-opt label=disable` : sur un hôte avec SELinux (Fedora, RHEL), Podman range un
  conteneur à systemd dans le domaine `container_init_t`, qui refuse la mémoire exécutable,
  et SQL Server meurt à son premier démarrage. Sans effet sur un hôte sans SELinux.
- `--cap-add NET_ADMIN` et `--cap-add NET_RAW` : la ressource `IPaddr2` ajoute l'adresse virtuelle à
  `eth0` et l'annonce par ARP gratuit. Sans `NET_RAW`, l'annonce échoue et les clients
  gardent l'adresse MAC de l'ancien primaire jusqu'à l'expiration de leur cache (34 secondes
  de plus, mesuré).
- Le nom `agpcs` n'est inscrit dans aucun DNS : on se connecte par l'adresse 10.89.50.20.

## Démonter

    ./extra/pacemaker/down.sh           # les nœuds et le réseau ; l'image reste
    podman start hadrlab1 hadrlab2 hadrlab3
    ENGINE=podman ./setup/test-lab.sh

## English

Optional lab of module 13: three Ubuntu 24.04 nodes running systemd, SQL Server 2025 CU7
and its `mssql-server-ha` package, Pacemaker and Corosync, the availability group `AgPcs`
in `CLUSTER_TYPE = EXTERNAL` with a configuration-only replica. Podman on Linux only, about
6 GB of free memory. Stop the course lab first (`ENGINE=podman ./setup/stop.sh`), build with
`./extra/pacemaker/all.sh`, remove with `./extra/pacemaker/down.sh`. Not run by the CI.
