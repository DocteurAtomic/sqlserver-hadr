# Exercice du module 11

Objectif : après la bascule d'un groupe de disponibilité ordinaire, rendre au nouveau primaire
la connexion de l'application et le travail de l'Agent qui n'existaient que sur l'ancien, et
faire en sorte que le travail n'agisse que sur le primaire, quel qu'il soit.

L'exercice crée sa base, `ex_objects`, et son groupe, `AgObjects`, à deux réplicas (`hadrlab1`
et `hadrlab2`, tous deux en validation synchrone). Il ne touche pas au groupe `AgPacha` des
démonstrations. `demos/module_11/99-cleanup.sh` retire le groupe, la base, la connexion et le
travail à la fin du module.

## Les fichiers

- `1-start.sh` retire ce qu'un essai précédent a laissé, puis crée sur `hadrlab1` la base
  `ex_objects` (table `dbo.Heartbeat`, où le travail écrit le nom de l'instance qui l'exécute),
  la connexion SQL `ex_app` (mot de passe `Ex-App-2026!`) avec son utilisateur, en lecture et
  en écriture, et le travail `ex_heartbeat`, une étape dans `ex_objects`. Il crée le groupe
  `AgObjects`, lance le travail une fois sur `hadrlab1`, puis bascule le groupe vers `hadrlab2`.
- `check.sh` dit ce qui manque.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. D'autres réponses sont
  justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_11/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_11/1-start.sh
./exercises/module_11/check.sh         # avec Podman : ENGINE=podman ./exercises/module_11/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Connectez-vous en `ex_app` à `hadrlab2`, le nouveau primaire, puis lisez le journal des
   erreurs de `hadrlab2`. Quelle raison donne-t-il ?
3. Recréez sur `hadrlab2` la connexion `ex_app` à l'identique de celle de `hadrlab1` : même
   SID, même mot de passe, sans écrire le mot de passe en clair.
4. Lancez le travail `ex_heartbeat` sur `hadrlab1`, devenu secondaire, et lisez son historique.
5. Donnez au travail une garde du primaire (`sys.fn_hadr_is_primary_replica`), et créez-le à
   l'identique sur `hadrlab1` et sur `hadrlab2`.
6. Lancez `check.sh`. Il sort en 0 quand tout tient.

`check.sh` lit l'état, jamais vos commandes. Il vérifie que `AgObjects` a un primaire et un
secondaire, `hadrlab1` et `hadrlab2` dans un sens ou dans l'autre ; que la connexion `ex_app`
existe sur les deux avec le SID de l'utilisateur `ex_app` de la base ; qu'elle se connecte au
primaire avec son mot de passe et y écrit une ligne ; que le travail `ex_heartbeat` existe sur
les deux, réussit sur les deux, et n'écrit que sur le primaire. Il lance le travail en `sa` :
`ex_app` n'a pas accès à `msdb` (Msg 229). Chaque passage de `check.sh` ajoute donc deux lignes
à `dbo.Heartbeat`.

## À réfléchir

- Rebasculez `AgObjects` vers `hadrlab1` (`setup/ag-failover.sh AgObjects hadrlab1`) et
  relancez `check.sh`. Faut-il toucher à quelque chose ?
- Pourquoi la première étape du travail ne peut-elle pas tourner dans `ex_objects` ?
- Que faudrait-il de plus pour un troisième réplica ? Et pour une deuxième connexion ?
