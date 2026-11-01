# Exercice du module 6

Objectif : basculer sans perte un groupe de disponibilité sans cluster, de `hadrlab1` vers
`hadrlab2`, et laisser après la bascule un groupe sain : l'ancien primaire secondaire et
synchronisé, le nouveau primaire qui accepte les écritures.

L'exercice crée sa base, `ex_bascule`, et son groupe, `AgBascule`, à deux réplicas (`hadrlab1`
et `hadrlab2`, tous deux en validation synchrone). Il ne touche pas au groupe `AgPacha` des
démonstrations. `demos/module_06/99-cleanup.sh` retire le groupe et supprime la base à la fin
du module.

## Les fichiers

- `1-start.sh` retire ce qu'un essai précédent a laissé (le groupe `AgBascule` sur chaque
  instance, quel que soit son rôle, puis `ex_bascule` et son historique), crée `ex_bascule`
  sur `hadrlab1` avec sa sauvegarde complète, crée `AgBascule`, attend que la copie de
  `hadrlab2` soit `SYNCHRONIZED`, puis écrit sur `hadrlab1` le lot `before failover`,
  500 lignes. La table `dbo.Registration` note pour chaque ligne l'instance qui l'a écrite
  (`written_on`).
- `check.sh` lit l'état de `hadrlab1` et de `hadrlab2` et dit ce qui manque.
- `solution/2-solution.sh` est un corrigé, à lire après avoir cherché. D'autres réponses sont
  justes : `check.sh` lit l'état, pas les commandes.

```bash
./exercises/module_06/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_06/1-start.sh
./exercises/module_06/check.sh         # avec Podman : ENGINE=podman ./exercises/module_06/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et dit ce qui manque.
2. Vérifiez sur `hadrlab1` que `hadrlab2` peut recevoir le rôle sans perte : son mode, son
   état de synchronisation, son dernier LSN durci comparé à celui du primaire.
3. Basculez `AgBascule` vers `hadrlab2` avec la séquence du clip 6.1, chaque instruction sur
   l'instance où elle agit. `ALTER AVAILABILITY GROUP ... FAILOVER` est refusé sans cluster.
4. Lisez l'état des deux copies, sur chaque instance. Tant qu'une copie reste suspendue,
   qu'obtenez-vous en lisant `ex_bascule` sur `hadrlab2` ? Pourquoi ?
5. Rendez le groupe sain : la copie de `hadrlab1` `SYNCHRONIZED`, et le réglage
   `REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT` remis à 0.
6. Écrivez sur `hadrlab2` au moins une ligne dans `ex_bascule.dbo.Registration` (la colonne
   `batch` est obligatoire), puis lancez `check.sh`. Il sort en 0 quand tout tient.

`check.sh` vérifie que `hadrlab1` est `SECONDARY` et `hadrlab2` `PRIMARY` dans `AgBascule` ;
que la copie de `hadrlab1`, lue sur `hadrlab2`, est `SYNCHRONIZED` et non suspendue ; que les
500 lignes du lot `before failover`, écrites sur `hadrlab1`, sont toutes sur `hadrlab2` ; qu'au
moins une ligne a été écrite sur `hadrlab2` ; et que le réglage est revenu à 0.

## À réfléchir

- Avec deux réplicas, que se passerait-il sur `hadrlab2` si vous laissiez le réglage à 1 et
  que `hadrlab1` s'arrêtait ?
- Combien de temps les écritures ont-elles été refusées pendant votre bascule ? Le corrigé
  ajoute sa durée à `evidence/module_06.md` ; le dernier module du cours la reprend.
- `AgPacha` a trois réplicas. Quelle instruction de plus faudrait-il, et sur quelle instance,
  pour y faire la même bascule ?
