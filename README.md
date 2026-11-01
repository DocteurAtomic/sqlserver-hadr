# SQL Server, la haute disponibilité

Labo du cours en ligne
[« SQL Server, la haute disponibilité »](https://www.docteuratomic.com) de Docteur Atomic.

## Le labo

Il faut Docker (ou Podman) avec `compose`, `curl` et un shell bash (sous Windows, WSL ou
Git Bash), et environ 7 Go de mémoire libre. Le poste doit être en x86-64 : Microsoft ne
prend en charge les images de SQL Server 2025 que sur un hôte Linux x86-64, et l'émulation
d'un Mac Apple Silicon n'est ni testée ni prise en charge.

    git clone https://github.com/DocteurAtomic/sqlserver-hadr.git
    cd sqlserver-hadr
    ./setup/install.sh

Avec Podman : `COMPOSE="podman compose" ENGINE=podman ./setup/install.sh`.

Le script télécharge la sauvegarde de `PachadataTraining` (626 Mo) et vérifie sa somme
SHA-256, démarre trois instances SQL Server 2025 Developer (`hadrlab1`, `hadrlab2`,
`hadrlab3`), chacune limitée à 2 Go et 2 processeurs, avec l'Agent SQL Server et la haute
disponibilité activés. Il restaure la base sur `hadrlab1` en mode de récupération complet
et en prend une sauvegarde complète, puis crée sur chaque instance un point de terminaison
authentifié par certificat et lui fait connaître les certificats des deux autres. Il finit
par `setup/test-lab.sh`, qui vérifie cet état et sort en erreur s'il n'est pas atteint.
Le script se relance sans dommage : il ne refait que ce qui manque.

Les trois instances partagent le volume `hadrlab-share`, monté sur
`/var/opt/mssql/share` : il tient la place du partage réseau des installations Windows
(sauvegardes, certificats, fichiers du log shipping). Il n'y a pas de cluster : les
groupes de disponibilité du labo sont en `CLUSTER_TYPE = NONE`.

| Instance | Depuis SSMS | Dans le réseau du labo |
|---|---|---|
| `hadrlab1` | `127.0.0.1,14631` | `hadrlab1` (1433), point de terminaison `tcp://hadrlab1:5022` |
| `hadrlab2` | `127.0.0.1,14632` | `hadrlab2` (1433), `tcp://hadrlab2:5022` |
| `hadrlab3` | `127.0.0.1,14633` | `hadrlab3` (1433), `tcp://hadrlab3:5022` |

Utilisateur `sa`, mot de passe `Hadr-2026!lab` (un mot de passe de labo, à ne jamais
reprendre ailleurs ; `MSSQL_SA_PASSWORD` le change avant le premier démarrage,
`SQLPORT1` à `SQLPORT3` changent les ports). Écrivez `127.0.0.1` plutôt que `localhost`,
et cochez *Trust server certificate* : les conteneurs n'ont qu'un certificat auto-signé.

Les noms `hadrlab1` à `hadrlab3` ne se résolvent que dans le réseau du labo. Une
redirection lecture-écriture ou un routage en lecture seule renvoie le client vers ces
noms : depuis SSMS sur votre poste, il échoue. Ces démonstrations se jouent avec le
`sqlcmd` d'un conteneur (`docker exec -it hadrlab3 /opt/mssql-tools18/bin/sqlcmd -C -S hadrlab2 -U sa ...`).

Arrêter le labo : `docker compose stop` ; le reprendre : `docker compose up -d`. Le
supprimer avec ses bases : `docker compose down -v`.

## La base

`PachadataTraining` est la base de démonstration anglaise de Pachadata : un organisme de
formation fictif, ses stages, sessions, inscriptions, factures et sa plateforme
d'e-learning. Les personnes sont fictives. Sa documentation est dans le dépôt
[rudi-bruchez/formations](https://github.com/rudi-bruchez/formations/tree/main/bases-exemples/PachadataTraining).
La sauvegarde n'est pas dans ce dépôt, le script la télécharge.

## Licence

Le code est sous licence MIT ([`LICENSE`](LICENSE)).

---

# SQL Server High Availability

Lab of the Docteur Atomic online course on SQL Server high availability. Run
`./setup/install.sh` (an x86-64 machine, Apple Silicon is not supported; Docker or Podman with compose, curl, bash, about 7 GB of free
memory; with Podman, `COMPOSE="podman compose" ENGINE=podman ./setup/install.sh`). It
downloads the `PachadataTraining` backup and checks its SHA-256, starts three SQL Server
2025 Developer instances (`hadrlab1` to `hadrlab3`, 2 GB and 2 processors each, Agent and
HADR on, ports 14631 to 14633 on 127.0.0.1), restores the database on `hadrlab1` in the
full recovery model with a first full backup, creates a certificate-authenticated endpoint
on each instance and exchanges the certificates through the shared volume
`/var/opt/mssql/share`, then runs `setup/test-lab.sh`, which exits with 1 when the lab is
not in that state. There is no cluster: the lab's availability groups use
`CLUSTER_TYPE = NONE`. The instance names only resolve inside the lab network, so
read-write redirection and read-only routing are demonstrated from a container's
`sqlcmd`, not from SSMS on the host. User `sa`, lab password `Hadr-2026!lab`; check
*Trust server certificate* in SSMS. The code is released under the MIT license.
