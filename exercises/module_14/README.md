# Exercice du module 14

Objectif : répondre à la direction de PachaData, chiffres à l'appui. Pour chaque solution du
cours, combien de transactions elle peut perdre (le RPO) et combien de temps le site
d'inscription reste coupé (le RTO), avec vos mesures, celles que les démonstrations et les
exercices ont écrites dans `evidence/` sur votre machine depuis le module 1.

L'exercice ne touche ni au labo ni à `evidence/`. Il lit vos fichiers de mesures et le rapport
que vous écrivez.

## Les fichiers

- `1-start.sh` écrit `report.md`, le rapport à remplir, ignoré par git, et liste ce que contient
  `evidence/`, fichier par fichier. Un rapport déjà présent est gardé sous `report.previous.md`.
- `check.sh` lit votre rapport et vos mesures, et dit ce qui ne tient pas. Il vérifie que chaque
  chiffre du rapport se retrouve dans la ligne de mesure qu'il cite, avec la condition de cette
  mesure, et qu'une solution que vous avez mesurée cite au moins une de ses mesures.
- `solution/2-solution.sh` est un corrigé, à lire après avoir écrit le vôtre. Il remplit le
  rapport avec les mesures de votre machine, quelles qu'elles soient, en citant chaque ligne.

```bash
./exercises/module_14/1-start.sh
./exercises/module_14/check.sh
```

## La consigne

1. Lancez `1-start.sh`, puis `check.sh` : il sort en 1 et liste ce qui reste à remplir.
2. Ouvrez `evidence/`. Chaque ligne est une mesure datée, avec sa condition : « three
   containers on one host » pour votre labo, « trainer's Windows cluster » pour les sorties du
   cluster du cours lues au module 7.
3. Pour chaque solution, remplissez la ligne `RPO` et la ligne `RTO` en français ou en anglais,
   comme vous le diriez à la direction. Chaque ligne qui donne un chiffre finit par sa source :
   `[module_06.md:2]` est la deuxième ligne de `evidence/module_06.md`. Plusieurs sources
   peuvent se suivre. Recopiez les chiffres tels qu'ils sont mesurés (`4,6` ou `4.6`, `1 000`
   ou `1,000` passent), et dites la condition : « trois conteneurs » ou « three containers »,
   « cluster Windows » ou « Windows cluster ».
4. Une solution dont `evidence/` ne contient aucune mesure s'écrit « not measured » ou « non
   mesuré ». `check.sh` refuse ce mot quand la mesure existe.
5. Écrivez sous « What PachaData buys » ce que vous recommandez, et pourquoi.
6. Lancez `check.sh` jusqu'à ce qu'il sorte en 0.

## À réfléchir

- Un RPO mesuré au repos, sur trois conteneurs d'une même machine, que devient-il entre deux
  salles reliées par un vrai réseau ?
- Le RTO d'une bascule planifiée et celui d'une panne, est-ce le même chiffre ?
- Que perd une bascule forcée, et qui le sait au moment où elle est lancée ?

---

# Module 14 exercise

Goal: answer the management of PachaData with your own figures: for each solution of the
course, the RPO and the RTO measured on your machine, read from `evidence/`. `1-start.sh` writes
`report.md` (ignored by git); fill each RPO and RTO line, end every line holding a figure with
its source (`[module_06.md:2]`, the second line of `evidence/module_06.md`), copy the numbers as
measured and state the condition ("three containers on one host"). Write "not measured" only
where `evidence/` has nothing. `check.sh` reads the report and `evidence/`, never the solution;
`solution/2-solution.sh` fills the report from whatever measures are there.
