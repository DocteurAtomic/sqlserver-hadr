# Exercice du module 13 (facultatif)

Objectif : basculer le groupe `AgPcs` vers `pc2` par le cluster, y écrire une ligne, puis le
ramener sur `pc1`, sans laisser derrière soi de contrainte qui épinglerait le groupe.

Il demande le labo Pacemaker (`extra/pacemaker/README.md`), monté par
`./extra/pacemaker/all.sh`. `1-start.sh` remet `AgPcs` sur `pc1` s'il est ailleurs, retire
les contraintes d'emplacement qu'une bascule précédente aurait laissées, puis crée sur `pc1`
la base `ex_pcs` et sa table `Visit`, avec une ligne écrite sur `pc1`, et l'ajoute au groupe.
La colonne `server` de chaque ligne garde le nom de l'instance primaire au moment où elle a
été validée.

    ./extra/pacemaker/exercise/1-start.sh
    ./extra/pacemaker/exercise/check.sh

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Basculez le groupe vers `pc2` avec `pcs`, depuis n'importe quel nœud
   (`podman exec -it pc1 bash`, puis `pcs ...`). Le T-SQL n'est pas une option : essayez
   `ALTER AVAILABILITY GROUP AgPcs FAILOVER` sur `pc2` pour voir ce qu'il répond.
3. Pendant la bascule, depuis `pc3`, essayez de vous connecter par l'adresse virtuelle,
   10.89.50.20. Combien de temps reste-t-elle sans réponse ?
4. Quand une connexion par 10.89.50.20 arrive sur `pc2`, insérez une ligne dans
   `ex_pcs.dbo.Visit` (`INSERT dbo.Visit DEFAULT VALUES`, la colonne `server` se remplit
   seule).
5. Lisez les contraintes d'emplacement du cluster (`pcs constraint location --full`). La
   page de Learn sur la bascule sous Linux demande d'en retirer une après chaque bascule
   planifiée : y en a-t-il une ?
6. Ramenez le groupe sur `pc1`, puis lancez `check.sh`. Il répond « AgPcs went to pc2 and
   came back » et sort en 0.

`check.sh` lit l'état, jamais vos commandes : une ligne de `ex_pcs.dbo.Visit` validée sur
`pc2`, `ag_cluster-clone` promu sur `pc1`, aucune contrainte `cli-prefer` ni `cli-ban`, `pc1`
primaire du groupe dans SQL Server, la copie de `ex_pcs` sur `pc2` synchronisée, et une
connexion par l'adresse virtuelle qui arrive sur `pc1`. Juste après une bascule, la copie de
`pc2` peut être encore `NOT SYNCHRONIZING` quelques secondes : relancez-le.

## À réfléchir

- Learn écrit la commande avec `--master` et un nom de ressource en `-master`. Que répond
  `pcs` 0.11 à `--master` ? Et que fait `pcs resource move-with-constraint` ?
- Que se passerait-il, à la prochaine panne de `pc1`, si une contrainte `cli-prefer` vers
  `pc1` restait en place ?
- Le client de l'étape 3 a attendu plus longtemps que la promotion de `pc2` dans SQL
  Server. Qu'est-ce qui manquait encore à `pc2` ?
