# Erweiterungen

* [LoadBalancer mit IPv6 Range](metallb-IPv6.md)
* [Service Account pro Lehrperson](ServiceAccounts.md)

## Weitere Ideen

### cloud-init Script variabel aus Repository

Wir verwenden ein fixes GitLab-Ablageschema unter `https://gitlab.com/ch-tbz-it/stud`

Anstatt das cloud-init-Script von **lernmaas** zu verwenden, wird das jeweilige cloud-init-Script direkt aus dem passenden Modul-Repository geladen.

Das cloud-init-File liegt dabei immer unter:

    https://gitlab.com/ch-tbz-it/stud/<modul>/cloud-init.yaml

Dadurch ist das cloud-init eindeutig dem Modul zugeordnet und kann unabhängig gepflegt und versioniert werden.

