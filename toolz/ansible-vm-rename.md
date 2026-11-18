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

