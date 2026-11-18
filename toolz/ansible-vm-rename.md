Oui. Voici une approche pragmatique et robuste, en distinguant clairement les deux niveaux (souvent confondus) :

1. **Renommage de la machine** (hostname OS + `/etc/hosts`)
2. **Alignement avec l’inventaire Ansible**
3. **(Optionnel) Renommage de l’objet VM** dans l’hyperviseur (ex. VMware)

### 1. Playbook recommandé (machine + inventaire)

Le pattern le plus propre et maintenable est :

- L’inventaire Ansible contient déjà le **nouveau nom** souhaité (`inventory_hostname`).
- Le playbook force la machine à s’aligner dessus.

```yaml
---
- name: Aligner le hostname de la machine sur l'inventaire
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Optionnel : domaine si tu veux un FQDN
    # domain: example.lan

  tasks:
    - name: Définir le hostname cible (court ou FQDN)
      ansible.builtin.set_fact:
        target_hostname: "{{ inventory_hostname_short }}"
        # ou : "{{ inventory_hostname }}" si tu veux le FQDN complet

    - name: Changer le hostname système
      ansible.builtin.hostname:
        name: "{{ target_hostname }}"
        use: systemd          # recommandé sur la plupart des distros modernes
      when: ansible_hostname != target_hostname

    - name: Mettre à jour /etc/hosts (127.0.1.1)
      ansible.builtin.lineinfile:
        path: /etc/hosts
        regexp: '^127\.0\.1\.1'
        line: "127.0.1.1 {{ target_hostname }}{% if domain is defined %}.{{ domain }}{% endif %} {{ target_hostname }}"
        state: present
        backup: true

    - name: Optionnel - Reboot si nécessaire
      ansible.builtin.reboot:
        msg: "Reboot après renommage hostname"
        reboot_timeout: 300
      when: ansible_hostname != target_hostname   # ou une variable explicite
```

**Pourquoi c’est solide :**
- Utilise uniquement des modules officiels (`ansible.builtin`).
- Idempotent.
- Le module `hostname` **ne touche pas** `/etc/hosts` (c’est volontaire et documenté) → on le fait explicitement.
- Tu contrôles le nom via l’inventaire (source de vérité).

**Workflow inventaire :**
1. Tu modifies ton inventaire (INI, YAML, ou dynamic inventory) pour que le host s’appelle déjà le nouveau nom.
2. Tu lances le playbook.
3. La machine s’aligne.

### 2. Ressources existantes intéressantes

| Ressource | Type | Intérêt | Remarque |
|-----------|------|---------|----------|
| [codylane/ansible-playbook-change-hostname](https://github.com/codylane/ansible-playbook-change-hostname) | Playbook simple | Fait exactement hostname + `/etc/hosts` + reboot + validation | Un peu daté (syntaxe ancienne), mais clair |
| **robertdebock.roles.hostname** (Galaxy) | Role | Très bien testé (molecule), propre | `hostname: "{{ inventory_hostname_short }}"` par défaut + reboot optionnel |
| Docs officielles `ansible.builtin.hostname` | Module | Référence | Ne modifie **pas** `/etc/hosts` |

### 3. Renommage de l’objet VM dans l’hyperviseur (VMware)

Si tu veux aussi renommer la VM elle-même dans vCenter :

- Module moderne recommandé : `community.vmware.vmware_object_rename`
- Ancienne méthode (toujours documentée) : récupérer l’UUID avec `vmware_guest_facts` puis renommer avec `vmware_guest`

Exemple minimal :

```yaml
- name: Renommer une VM VMware
  community.vmware.vmware_object_rename:
    hostname: "{{ vcenter_hostname }}"
    username: "{{ vcenter_username }}"
    password: "{{ vcenter_password }}"
    validate_certs: false
    object_name: "{{ old_vm_name }}"
    object_type: VirtualMachine
    new_name: "{{ new_vm_name }}"
  delegate_to: localhost
```

Documentation officielle :  
https://docs.ansible.com/projects/ansible/latest/scenario_guides/vmware_scenarios/scenario_rename_vm.html

### Recommandation pratique

- Pour **99 % des cas** (alignement inventaire ↔ machine) : utilise le playbook ci-dessus ou le role `robertdebock.hostname`.
- Ne mélange pas le renommage hyperviseur et le renommage OS dans le même play sans bien séquencer (et souvent il vaut mieux les séparer).
- Inventaire = source de vérité. C’est plus maintenable que de pousser un nom depuis la machine.

Tu utilises plutôt VMware, Proxmox, libvirt, ou du bare-metal / cloud ? Je peux adapter le playbook précisément.








Et inventory:

**Oui, on peut le faire**, mais il faut être clair sur la réalité technique :

Ansible **n’a pas** de module officiel `rename_host` qui modifie de façon permanente un inventaire statique pendant l’exécution d’un play.
`add_host` ne touche **que l’inventaire en mémoire** (pour le run courant).

Pour un renommage **persistant** dans un inventaire fichier (INI ou YAML), le playbook doit **éditer le fichier** lui-même (généralement depuis `localhost`).

### Playbook complet recommandé (inventaire + machine)

```yaml
---
- name: Renommage inventaire + hostname machine
  hosts: localhost
  gather_facts: false
  vars:
    inventory_file: "./inventory.ini"          # adapte le chemin
    old_hostname: "old-vm-01"
    new_hostname: "new-vm-01"
    # domain: "example.lan"                    # optionnel

  tasks:
    - name: Vérifier que l'ancien nom existe dans l'inventaire
      ansible.builtin.shell: |
        grep -E '^\s*{{ old_hostname }}(\s|$)' {{ inventory_file }}
      register: check_old
      changed_when: false
      failed_when: check_old.rc != 0

    - name: Backup de l'inventaire
      ansible.builtin.copy:
        src: "{{ inventory_file }}"
        dest: "{{ inventory_file }}.bak.{{ ansible_date_time.epoch }}"
        remote_src: true
        mode: preserve

    - name: Renommer l'hôte dans l'inventaire INI
      ansible.builtin.replace:
        path: "{{ inventory_file }}"
        regexp: '(?m)^(\s*){{ old_hostname }}(\s|$)'
        replace: '\1{{ new_hostname }}\2'
      # Alternative plus sûre si tu veux seulement la première occurrence :
      # ansible.builtin.lineinfile avec regexp + line

    - name: Afficher le résultat
      ansible.builtin.debug:
        msg: "Inventaire renommé : {{ old_hostname }} → {{ new_hostname }}"

# --- Deuxième play : appliquer le nouveau nom sur la machine ---
- name: Aligner le hostname OS sur le nouvel inventaire
  hosts: "{{ new_hostname }}"          # attention : il faut que le nouvel inventaire soit déjà chargé
  become: true
  gather_facts: true
  tasks:
    - name: Définir le hostname cible
      ansible.builtin.set_fact:
        target_hostname: "{{ inventory_hostname_short }}"

    - name: Changer le hostname système
      ansible.builtin.hostname:
        name: "{{ target_hostname }}"
        use: systemd
      when: ansible_hostname != target_hostname

    - name: Mettre à jour /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        regexp: '^127\.0\.1\.1'
        line: "127.0.1.1 {{ target_hostname }}{% if domain is defined %}.{{ domain }}{% endif %} {{ target_hostname }}"
        backup: true
```

### Comment l’utiliser

```bash
# 1. Éditer le playbook (ou passer les vars en -e)
ansible-playbook rename-vm.yml \
  -e "old_hostname=old-vm-01 new_hostname=new-vm-01 inventory_file=./hosts.ini"

# 2. Après le premier play, l'inventaire est modifié sur disque.
#    Pour le deuxième play, soit tu recharges, soit tu utilises -i avec le fichier modifié.
```

### Points importants / limites

| Point | Détail |
|-------|--------|
| **Format INI** | Le `replace` ci-dessus fonctionne bien. |
| **Format YAML** | Plus délicat. Préfère un template Jinja2 ou un petit script Python pour modifier la structure. |
| **Groupes / vars** | Le renommage simple ne déplace pas les `host_vars/` ni les références dans d’autres fichiers. À gérer manuellement ou avec un script. |
| **Sécurité** | Toujours faire un backup. Ne pas lancer ça en parallèle sur plusieurs hosts sans précaution. |
| **Meilleure pratique long terme** | Inventaire en Git + PR, ou inventaire dynamique (NetBox, AWX, cloud inventory). Éditer le fichier depuis un playbook reste un contournement. |

### Version plus robuste pour YAML (recommandée si tu es en YAML)

```yaml
- name: Renommer dans un inventaire YAML
  hosts: localhost
  tasks:
    - name: Charger l'inventaire
      ansible.builtin.include_vars:
        file: inventory.yml
      register: inv

    # Puis utiliser un template ou un module python pour réécrire le fichier
    # avec le nouveau nom. C’est plus sûr que du regex sur du YAML.
```

---

**Tu utilises plutôt un inventaire INI ou YAML ?**
Et tu veux aussi que le playbook gère automatiquement le renommage dans `host_vars/` ou juste le fichier d’inventaire principal ? Je peux te donner la version exacte adaptée.









Pure yaml:

Oui, pour les inventaires **YAML** c’est plus délicat qu’en INI.
Il n’existe pas de module officiel qui renomme proprement un host dans un inventaire YAML (structure imbriquée + groupes + children + host_vars).

La solution la plus robuste et maintenable est d’utiliser un petit script Python appelé depuis le playbook (lecture → modification de la structure → écriture propre avec `yaml.dump`).

### Playbook complet (YAML inventory + hostname machine)

```yaml
---
- name: Renommage inventaire YAML + hostname machine
  hosts: localhost
  gather_facts: false
  vars:
    inventory_file: "./inventory.yml"          # chemin de ton inventaire
    old_hostname: "old-vm-01"
    new_hostname: "new-vm-01"

  tasks:
    - name: Backup de l'inventaire
      ansible.builtin.copy:
        src: "{{ inventory_file }}"
        dest: "{{ inventory_file }}.bak.{{ ansible_date_time.epoch }}"
        remote_src: true
        mode: preserve

    - name: Renommer l'hôte dans l'inventaire YAML (script Python)
      ansible.builtin.shell: |
        python3 << 'EOF'
        import yaml
        import sys

        inventory_file = "{{ inventory_file }}"
        old = "{{ old_hostname }}"
        new = "{{ new_hostname }}"

        with open(inventory_file, "r") as f:
            data = yaml.safe_load(f)

        def rename_host(obj):
            if isinstance(obj, dict):
                # Cas hosts: { old: {vars} }
                if "hosts" in obj and isinstance(obj["hosts"], dict):
                    if old in obj["hosts"]:
                        obj["hosts"][new] = obj["hosts"].pop(old)
                # Parcours récursif (children, etc.)
                for k, v in list(obj.items()):
                    rename_host(v)
            elif isinstance(obj, list):
                for item in obj:
                    rename_host(item)

        rename_host(data)

        with open(inventory_file, "w") as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

        print(f"Renommé : {old} → {new}")
        EOF
      args:
        executable: /bin/bash
      register: rename_result
      changed_when: true

    - name: Afficher le résultat
      ansible.builtin.debug:
        msg: "{{ rename_result.stdout }}"

# --- Optionnel : appliquer le nouveau nom sur la machine ---
# (à lancer dans un second temps, ou après avoir rechargé l'inventaire)
# - name: Aligner le hostname OS
#   hosts: "{{ new_hostname }}"
#   become: true
#   tasks:
#     - ansible.builtin.hostname:
#         name: "{{ inventory_hostname_short }}"
#         use: systemd
```

### Utilisation

```bash
ansible-playbook rename-inventory.yml \
  -e "old_hostname=old-vm-01 new_hostname=new-vm-01 inventory_file=./hosts.yml"
```

### Points importants

| Point | Détail |
|-------|--------|
| **Portée** | Le script parcourt récursivement et renomme le host partout où il apparaît sous une clé `hosts:` (fonctionne avec groupes imbriqués, children, etc.). |
| **host_vars/** | Ce playbook ne renomme **pas** automatiquement les fichiers dans `host_vars/`. Il faut le faire séparément (ou étendre le script). |
| **Sauvegarde** | Un `.bak` est créé avant modification. |
| **Dépendance** | Nécessite `python3` + `pyyaml` sur le control node (`pip install pyyaml` si besoin). |
| **Idempotence** | Pas parfaite (toujours `changed`). Tu peux ajouter une vérification préalable si tu veux. |

### Variante plus propre (recommandée en production)

Tu peux extraire le script Python dans un fichier `rename_host.py` et l’appeler avec `ansible.builtin.script` ou `ansible.builtin.command`. C’est plus lisible et testable.

---

**Tu veux que je te donne aussi la version qui gère le renommage des fichiers `host_vars/` en même temps ?**
Ou tu préfères une version qui ne touche que l’inventaire principal ?













# Final:
Oui. Voici la version complète qui gère **à la fois** :

- Le renommage dans l’inventaire YAML
- Le renommage des fichiers/dossiers `host_vars/`

```yaml
---
- name: Renommage inventaire YAML + host_vars + hostname machine
  hosts: localhost
  gather_facts: false
  vars:
    inventory_file: "./inventory.yml"
    host_vars_dir: "./host_vars"               # dossier host_vars
    old_hostname: "old-vm-01"
    new_hostname: "new-vm-01"

  tasks:
    - name: Backup de l'inventaire
      ansible.builtin.copy:
        src: "{{ inventory_file }}"
        dest: "{{ inventory_file }}.bak.{{ ansible_date_time.epoch }}"
        remote_src: true
        mode: preserve

    - name: Renommer l'hôte dans l'inventaire YAML + host_vars
      ansible.builtin.shell: |
        python3 << 'EOF'
        import yaml
        import os
        import shutil
        from pathlib import Path

        inventory_file = "{{ inventory_file }}"
        host_vars_dir = "{{ host_vars_dir }}"
        old = "{{ old_hostname }}"
        new = "{{ new_hostname }}"

        # --- 1. Renommage dans l'inventaire YAML ---
        with open(inventory_file, "r") as f:
            data = yaml.safe_load(f)

        def rename_host(obj):
            if isinstance(obj, dict):
                if "hosts" in obj and isinstance(obj["hosts"], dict):
                    if old in obj["hosts"]:
                        obj["hosts"][new] = obj["hosts"].pop(old)
                        print(f"Inventaire : renommé {old} → {new}")
                for k, v in list(obj.items()):
                    rename_host(v)
            elif isinstance(obj, list):
                for item in obj:
                    rename_host(item)

        rename_host(data)

        with open(inventory_file, "w") as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

        # --- 2. Renommage dans host_vars ---
        hv_path = Path(host_vars_dir)
        if not hv_path.exists():
            print("Aucun dossier host_vars trouvé, on passe.")
            exit(0)

        # Cas 1 : host_vars/old-hostname.yml
        old_file = hv_path / f"{old}.yml"
        old_file_yaml = hv_path / f"{old}.yaml"
        new_file = hv_path / f"{new}.yml"

        if old_file.exists():
            shutil.move(str(old_file), str(new_file))
            print(f"host_vars : {old}.yml → {new}.yml")
        elif old_file_yaml.exists():
            shutil.move(str(old_file_yaml), str(hv_path / f"{new}.yaml"))
            print(f"host_vars : {old}.yaml → {new}.yaml")

        # Cas 2 : dossier host_vars/old-hostname/
        old_dir = hv_path / old
        new_dir = hv_path / new
        if old_dir.is_dir():
            shutil.move(str(old_dir), str(new_dir))
            print(f"host_vars : dossier {old}/ → {new}/")

        print("Renommage terminé.")
        EOF
      args:
        executable: /bin/bash
      register: rename_result
      changed_when: true

    - name: Afficher le résultat
      ansible.builtin.debug:
        msg: "{{ rename_result.stdout_lines }}"

# --- Optionnel : appliquer le hostname sur la machine ---
# (à lancer après rechargement de l'inventaire)
# - name: Aligner le hostname OS
#   hosts: "{{ new_hostname }}"
#   become: true
#   tasks:
#     - ansible.builtin.hostname:
#         name: "{{ inventory_hostname_short }}"
#         use: systemd
```

### Ce que ça gère

| Élément | Action |
|---------|--------|
| Inventaire YAML | Renomme le host dans toutes les sections `hosts:` (récursif) |
| `host_vars/old.yml` | Renommé en `host_vars/new.yml` |
| `host_vars/old.yaml` | Renommé en `host_vars/new.yaml` |
| `host_vars/old/` (dossier) | Renommé en `host_vars/new/` |
| Backup | Fichier `.bak` de l’inventaire avant modification |

### Utilisation

```bash
ansible-playbook rename-inventory.yml \
  -e "old_hostname=old-vm-01 new_hostname=new-vm-01 \
      inventory_file=./hosts.yml \
      host_vars_dir=./host_vars"
```

### Remarques importantes

- Le script ne modifie **pas** le contenu des fichiers `host_vars` (uniquement le nom du fichier/dossier). Si tu as des références au vieux hostname à l’intérieur des fichiers, il faudra les traiter séparément.
- Si tu as des `group_vars` ou d’autres fichiers qui référencent le hostname, ils ne sont pas touchés.
- Toujours tester sur une copie avant de lancer en prod.

Tu veux aussi que le script cherche et remplace les occurrences de l’ancien hostname **à l’intérieur** des fichiers `host_vars` ? Ou c’est suffisant comme ça ?
