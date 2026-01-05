Module laut modulbaukasten.ch
=============================

Umgebung für Modul ${modul}

Intro
-----

%{ for idx in range(length(vms)) ~}
- ${idx + 1}. https://${vms[idx]}
%{ endfor ~}

SSH Zugriff
-----------

%{ for idx in range(length(vms)) ~}
ssh -i ~/.ssh/lerncloud ubuntu@${vms[idx]}
%{ endfor ~}
