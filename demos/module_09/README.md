# Démonstrations du module 9

Le module 9 présente l'instance de cluster de basculement (FCI) et la compare au groupe de
disponibilité. Il n'a pas de démonstration de FCI ni d'exercice : le cluster Windows du
formateur n'a pas de stockage partagé, et une FCI en exige un. Les deux scripts ci-dessous lisent,
sur ce cluster, ce que SQL Server et le cluster disent de l'instance, et montrent qu'un nœud de
groupe de disponibilité n'est pas une FCI. Ils ne modifient rien.

| Script | Où | Clip |
|---|---|---|
| `01-instance-or-group.sql` | `SQL01`, puis `SQL02`, dans `sqlcmd` | 9.1 et 9.2 : `IsClustered`, les vues d'une FCI (vides), le cluster vu du groupe, le groupe autonome |
| `02-cluster-resources.ps1` | `SQL01`, puis `SQL02`, PowerShell administrateur | 9.1 : les rôles et ressources du cluster, les types de ressources SQL Server, les disques, les services du nœud |

`setup/run-scripts.sh` ne lance rien de ce module : le script SQL porte `ci: skip`, et le script
PowerShell n'est pas un script du labo. Sur vos conteneurs, la première requête de
`01-instance-or-group.sql` rend aussi `IsClustered` à 0 (module 1, `03-edition.sql`).

---

# Module 9 demos

Module 9 presents the failover cluster instance (FCI) and compares it with the availability
group. It has no FCI demo and no exercise: the trainer's Windows cluster has no shared storage,
which an FCI requires. The two scripts read, on that cluster, what SQL Server and the cluster say
about the instance, and show that a node of an availability group is not an FCI. They change
nothing. `setup/run-scripts.sh` runs nothing from this module.
