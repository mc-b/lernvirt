Module laut modulbaukasten.ch
=============================

Services
--------

Development:
- https://${development_fqdn}:4200       - Terminal im Browser. User: ubuntu, Password insecure

Build (CI/CD):
- https://${vm_fqdn}:4200                - Terminal im Browser. User: ubuntu, Password insecure

SSH Zugriff
-----------

ssh -i ~/.ssh/lerncloud ubuntu@${development_fqdn}

ssh -i ~/.ssh/lerncloud ubuntu@${vm_fqdn}
    