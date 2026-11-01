# Exercice du module 1

Objectif : choisir une solution de haute disponibilité pour chacune de trois bases de
PachaData, à partir de son RPO, de son RTO et de l'édition que PachaData paie.

La direction a fait le tour des équipes. Elle a obtenu trois bases, et pour chacune ce que le
métier accepte de perdre (le RPO, en secondes) et le temps d'arrêt qu'il accepte (le RTO, en
secondes). PachaData paie l'édition Standard. L'équipe du site d'inscription ajoute une
remarque : le site lit `Billing` dans les mêmes requêtes que `Registration`, et elle voudrait
que les deux bases basculent ensemble.

L'exercice se joue sur `hadrlab1`, dans une base `ex_needs` que le script de départ crée.
Il n'écrit rien d'autre sur le labo. `demos/module_01/99-cleanup.sh` la supprime à la fin du
module.

## Les fichiers

- `1-start.sql` crée `ex_needs` : les besoins (`dbo.Need`), l'édition (`dbo.Licence`), les
  solutions parmi lesquelles choisir (`dbo.Solution`) et la table de vos choix, vide
  (`dbo.Choice`). Le relancer efface vos choix et repart de zéro.
- `check.sh` contrôle vos choix, et dit ce qui ne tient pas.
- `solution/2-solution.sql` est un corrigé, à lire après avoir cherché. D'autres réponses
  sont justes : `check.sh` les accepte.

```bash
docker exec -i hadrlab1 /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -I < exercises/module_01/1-start.sql
./exercises/module_01/check.sh        # avec Podman : ENGINE=podman ./exercises/module_01/check.sh
```

## La consigne

1. Lisez `dbo.Need`, `dbo.Licence` et `dbo.Solution`.
2. Pour chaque base, écrivez une ligne dans `dbo.Choice` : la solution (`solution`, un code
   de `dbo.Solution`), le nom du groupe pour un groupe de disponibilité (`group_name`), et la
   raison du choix en une ou deux phrases (`reason`).
3. Lancez `check.sh`. Il sort en 0 quand vos choix tiennent, en 1 sinon.

`check.sh` refuse ce qui ne peut pas marcher : une base sans choix ou sans raison, une
solution qui perd des données là où le RPO vaut 0, une solution de l'édition Enterprise sur
une édition Standard, deux bases dans un même groupe de disponibilité en édition Standard.
Il accepte le reste : entre deux solutions qui tiennent, c'est votre raison qui décide.

## À réfléchir

- `Registration` et `Billing` ne peuvent pas être dans un même groupe de base. Quelles
  solutions les feraient basculer ensemble, et que coûte chacune ?
- Un RTO de 60 secondes demande une bascule automatique. Qu'est-ce qui la décide, sur un
  groupe de disponibilité ? Le labo du cours l'a-t-il ?
- `Elearning` accepte de perdre une journée. Qu'est-ce qui reste indispensable, même pour
  elle ?
