# Mise à jour rolling d'un cluster CTDB/NFS

> Runbook + scripts + playbook Ansible pour mettre à jour un nœud d'un cluster CTDB/NFS
> en s'assurant qu'il est **passif** (drain complet) avant l'upgrade.
>
> ⚠️ Corrigé par rapport à la première version : coquille dans la boucle d'attente du script shell (ligne parasite `ctdb log ...`), remplacée par un `done` propre.

---

## 1. Principe

CTDB gère les **IP publiques (VIP)** du cluster. Rendre un nœud "passif" = le **désactiver**
pour qu'il ne porte plus aucune VIP, et attendre qu'**aucun client NFS** ne soit encore
accroché — alors seulement on lance l'upgrade.

Spécificités NFS :

- Les VIP sont portées par l'event script **`60.nfs`** : le drain se fait toujours via `ctdb disable`,
  CTDB remonte automatiquement les exports et l'état des verrous sur l'autre nœud.
- Un upgrade/reboot avec des clients actifs coupe des I/O bloquantes côté client
  (hang des `hard mounts`). On attend donc zéro client NFS.
- **NFSv4 / 4.1+** : pas de `statd`, le client gère son état via les leases ; bascule transparente
  sur la VIP reprise par l'autre nœud.
- **NFSv3** : verrous `statd`/`lockd` gérés par l'event script CTDB `60.nfs`. On attend que
  `/var/lib/nfs/sm` se vide (plus de verrou à récupérer).

### Commandes ctdb

| Commande | Effet | Usage |
|---|---|---|
| `ctdb disable -n <n>` | Le nœud ne prend plus aucune IP, démon reste OK | **Recommandé** pour la maintenance |
| `ctdb ban -n <n>` | Idem, temporaire (auto-levé après délai) | Diagnostic court — à éviter pour un upgrade |
| `ctdb stop -n <n>` | Désactive + empêche samba/nfs de tourner | Si on veut aussi couper les services |

⚠️ Ne **jamais** tuer les VIP ou down une interface à la main : CTDB marquerait le nœud
`UNHEALTHY` et déclencherait une bascule non maîtrisée. Toujours passer par `disable`.

---

## 2. Process de mise à jour

```
1. Contrôle cluster sain      -> ctdb -n all nodestatus : tous OK, un recovery master
2. Drain                      -> ctdb disable -n <self>
3. Vérification VIP           -> ctdb ip : 0 VIP sur ce nœud, toutes portées par l'autre
4. Vérification clients       -> /proc/fs/nfsd/clients vide + /var/lib/nfs/sm vide
5. Upgrade / reboot
6. Reprise                    -> services NFS up, ctdb enable, vérif VIP + test montage
```

Ordre de mise à jour : **drain A → upgrade A → resume A → drain B → upgrade B → resume B**.
Jamais les 2 nœuds en même temps ; `enable` seulement si l'autre nœud est OK.

---

## 3. Standalone : `ctdb-upgrade.sh`

Deux sous-commandes pour être utilisable dans une runbook manuelle :

```bash
./ctdb-upgrade.sh drain    # met le nœud en passif (sécurisé, abort si problème)
# --> VRAI upgrade / reboot ICI
./ctdb-upgrade.sh resume   # redonne le nœud au cluster et vérifie
```

```bash
#!/usr/bin/env bash
# ============================================================================
# ctdb-upgrade.sh
#
# Process de mise à jour d'un nœud CTDB dans un cluster NFS.
#
#   ./ctdb-upgrade.sh drain    -> met le nœud en "passif" :
#                                 1. contrôle que le reste du cluster est sain
#                                 2. ctdb disable  (drain des IP publiques)
#                                 3. attente de la fin des connexions NFS
#                                 4. STOPpe les services NFS locaux
#   ./ctdb-upgrade.sh resume   -> après l'upgrade/reboot :
#                                 1. redémarre les services NFS
#                                 2. ctdb enable (takeover des VIP possibles)
#                                 3. vérifie l'état du cluster + test montage
#
# NE lance PAS l'upgrade lui-même : il prépare / restaure l'environnement.
# Dépendances : ctdb, ss, awk. Optionnel : showmount, rpcinfo.
# Exécution : root, sur le nœud à mettre à jour.
# ============================================================================

set -euo pipefail

# ----------------------------- Configuration --------------------------------
CTDB_BIN="${CTDB_BIN:-/usr/bin/ctdb}"
DRAIN_TIMEOUT=300            # attente max du drain des VIP (s)
CLIENT_TIMEOUT=900           # attente max de disparition des clients NFS (s)
POLL=5                       # intervalle de sondage (s)

NFS_PORT=2049                # port kernel NFSD
NFS_SERVICES=(nfs-server rpcbind)   # adaptez (nfs-ganesha si Ganesha)

LOCKFILE=/var/run/ctdb-upgrade-drain.lock

log()  { echo "[$(date '+%F %T')] $*"; }
die()  { log "ERREUR: $*"; exit 1; }

# Numéro du nœud CTDB local
get_self_node() {
    [ -x "$CTDB_BIN" ] || die "$CTDB_BIN introuvable"
    line="$("$CTDB_BIN" -n all status | grep "$(hostname -I | awk '{print $1}')" | head -1)"
    node="$(echo "$line" | awk '{sub(":","",$1); print $1}')"
    [ -n "$node" ] || die "impossible de résoudre le numéro de nœud ctdb local"
    echo "$node"
}

# Nœuds peers (tous sauf nous)
get_other_nodes() {
    "$CTDB_BIN" -n all status | awk -v self="$SELF_NODE" \
        '($1 ~ /^[0-9]+:$/) { sub(":","",$1); if ($1 != self) print $1 }'
}

# VIP actuellement portées par le nœud local
local_vip_count() {
    "$CTDB_BIN" ip | awk -v self="$SELF_NODE" \
        '{ n = $NF; sub(":","",n); if (n == self) c++ } END { print c+0 }'
}

# Clients NFS kernel actifs sur CE nœud (kernel >= 5.3)
nfs_client_count() {
    if [ -d /proc/fs/nfsd/clients ]; then
        find /proc/fs/nfsd/clients -mindepth 1 -maxdepth 1 -type d | wc -l
    else
        ss -tH state established "( sport = :$NFS_PORT or dport = :$NFS_PORT )" 2>/dev/null | wc -l
    fi
}

# Verrous NFSv3 restants (statd)
nfs_v3_locks_count() {
    if [ -d /var/lib/nfs/sm ]; then
        find /var/lib/nfs/sm -mindepth 1 -maxdepth 1 | wc -l
    else
        echo 0
    fi
}

# ---------------------------------------------------------------- sub-commandes

precheck() {
    log "1/5  Contrôle de santé du cluster (peer nodes)"
    local bad=0
    while read -r -u 3 n; do
        state="$("$CTDB_BIN" -n "$n" nodestatus | awk '{print $2}')"
        if [ "$state" != "OK" ] && [ "$state" != "DISABLED" ]; then
            log "     NŒUD $n : état '$state' -> NON OK pour maintenance"
            bad=1
        else
            log "     NŒUD $n : $state"
        fi
    done 3< <(get_other_nodes)
    [ "$bad" -eq 0 ] || die "un nœud peer n'est pas sain, ABORT"
    log "     Ce nœud: état '$("$CTDB_BIN" nodestatus | awk '{print $2}')'"
}

do_drain() {
    if ! mkdir "$(dirname "$LOCKFILE")" 2>/dev/null; true; fi
    if ! mkdir "$LOCKFILE" 2>/dev/null; then
        die "un drain est déjà en cours (lock: $LOCKFILE)"
    fi
    trap 'rmdir "$LOCKFILE" 2>/dev/null' EXIT

    precheck

    log "2/5  Drain : ctdb disable -n $SELF_NODE"
    "$CTDB_BIN" disable -n "$SELF_NODE" || die "disable a échoué"

    log "3/5  Attente libération des IP publiques (timeout ${DRAIN_TIMEOUT}s)"
    elapsed=0
    while [ "$(local_vip_count)" -ne 0 ]; do
        sleep "$POLL"; elapsed=$((elapsed + POLL))
        if [ "$elapsed" -ge "$DRAIN_TIMEOUT" ]; then
            "$CTDB_BIN" -n all status
            "$CTDB_BIN" ip
            die "des VIP sont encore portées après ${DRAIN_TIMEOUT}s"
        fi
        log "     VIP restantes : $(local_vip_count) — attente (${elapsed}s)"
    done
    log "     0 VIP portée par ce nœud — distribution VIP:"
    "$CTDB_BIN" ip | sed 's/^/     /'

    log "4/5  Attente fin des clients NFS (timeout ${CLIENT_TIMEOUT}s)"
    elapsed=0
    while :; do
        c="$(nfs_client_count)"
        v3="$(nfs_v3_locks_count)"
        if [ "$c" -eq 0 ] && [ "$v3" -eq 0 ]; then
            log "     aucun client NFS / verrou NFSv3 restant"
            break
        fi
        if [ "$elapsed" -ge "$CLIENT_TIMEOUT" ]; then
            log "     clients kernel : $c"
            log "     verrous NFSv3  : $v3"
            log "     -> showmount -a localhost ; ss -tunap | grep $NFS_PORT"
            die "clients encore raccrochés après ${CLIENT_TIMEOUT}s"
        fi
        sleep "$POLL"; elapsed=$((elapsed + POLL))
        log "     clients: $c, verrous v3: $v3 — attente (${elapsed}s)"
    done

    log "5/5  Arrêt des services NFS locaux, le nœud est PASSIF"
    for svc in "${NFS_SERVICES[@]}"; do
        systemctl stop "$svc" 2>/dev/null && log "     stopped $svc" || log "     (skip) $svc"
    done

    touch /var/run/ctdb-upgrade-drain.done
    log "NŒUD PASSIF — lancez maintenant l'upgrade / le reboot."
    log "Apres : ./ctdb-upgrade.sh resume"
}

do_resume() {
    [ -f /var/run/ctdb-upgrade-drain.done ] \
        || die "pas de drain 'propre' détecté (/var/run/ctdb-upgrade-drain.done manquant)"

    log "1/4  Redémarrage des services NFS (rpcbind d'abord)"
    for svc in rpcbind nfs-server; do
        systemctl start "$svc" && log "     started $svc" || die "start $svc a échoué"
    done
    rpcinfo -t localhost nfs 4 >/dev/null 2>&1 || die "nfs v4 ne répond pas sur localhost"

    log "2/4  ctdb enable -n $SELF_NODE"
    "$CTDB_BIN" enable -n "$SELF_NODE" || die "ctdb enable a échoué"

    log "3/4  Attente stabilité du cluster"
    sleep 10
    while [ "$("$CTDB_BIN" nodestatus | awk '{print $2}')" != "OK" ]; do
        sleep 5; log "     nœud pas encore OK, attente..."
    done
    "$CTDB_BIN" -n all status | sed 's/^/     /'

    log "4/4  Distribution des VIP après takeover"
    "$CTDB_BIN" ip | sed 's/^/     /'
    rm -f /var/run/ctdb-upgrade-drain.done

    log "NŒUD ACTIF À NOUVEAU — valider un montage client sur une VIP avant de sortir."
}

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

# ----------------------------------------------------------------------- main
[ "$(id -u)" -eq 0 ] || die "à exécuter en root"
SELF_NODE="$(get_self_node)"
log "nœud CTDB local = $SELF_NODE ($(hostname))"

case "${1:-}" in
    drain)  do_drain ;;
    resume) do_resume ;;
    *)      usage ;;
esac
```

---

## 4. Ansible / AWX : playbook rolling upgrade

### Arborescence

```
nfs-ctdb-upgrade/
├── inventory.yaml            # [nfs_cluster] node1 node2
├── playbook.yaml
└── roles/ctdb-rolling-upgrade/
    ├── defaults/main.yaml
    └── tasks/
        ├── precheck.yaml
        ├── drain.yaml
        ├── upgrade.yaml
        ├── resume.yaml
        └── verify.yaml
```

### `inventory.yaml`

```ini
[nfs_cluster]
node1 ansible_host=10.0.0.11
node2 ansible_host=10.0.0.12

[nfs_cluster:vars]
ansible_user=patchadmin
ansible_become=true
```

### `playbook.yaml`

```yaml
---
- name: Rolling upgrade du cluster CTDB/NFS
  hosts: nfs_cluster
  become: true
  serial: 1                       # JAMAIS 2 nœuds en même temps
  max_fail_percentage: 0          # abort si le 1er nœud pose problème
  any_errors_fatal: true

  pre_tasks:
    - name: Refuser de lancer sans confirmation (AWX survey)
      ansible.builtin.assert:
        that:
          - upgrade_confirm | bool
        fail_msg: "Var 'upgrade_confirm' non renseignée (survey checkbox)"

  roles:
    - ctdb-rolling-upgrade
```

### `roles/ctdb-rolling-upgrade/defaults/main.yaml`

```yaml
upgrade_confirm: false
drain_timeout: 300              # s — attente libération VIP
client_timeout: 900             # s — attente disparition clients NFS
poll_interval: 5                # s
nfs_services_start: [rpcbind, nfs-server]
nfs_services_stop:  [nfs-server, rpcbind]
reboot_if_kernel_updated: true
verify_host: "10.0.0.200"       # une VIP de test
verify_export: "/export/data"
```

### `tasks/precheck.yaml`

```yaml
---
- name: Statut de tous les nœuds ctdb
  ansible.builtin.command: ctdb -n all status
  register: ctdb_status_all
  changed_when: false

- name: Vérifier qu'aucun peer n'est UNHEALTHY / BANNED / STOPPED / DISCONNECTED
  vars:
    peers: >-
      {{ ctdb_status_all.stdout.split('\n')
         | select('match', '^[0-9]+:') | list }}
  ansible.builtin.assert:
    that:
      - peers | reject('search', item) | length == 0
    fail_msg: "Peer non sain détecté — ABORT :\n{{ ctdb_status_all.stdout }}"
  with_items:
    - 'UNHEALTHY'
    - 'DISCONNECTED'
    - 'BANNED'
    - 'STOPPED'
```

### `tasks/drain.yaml`

```yaml
---
- name: Vérifier si le nœud est déjà DISABLED (idempotence reboot)
  ansible.builtin.shell: |
    ctdb nodestatus | grep -q DISABLED && echo yes || echo no
  register: already_drained
  changed_when: false

- name: ctdb disable (drain)
  ansible.builtin.command: ctdb disable
  when: already_drained.stdout == "no"

- name: Attendre 0 VIP portée par le nœud
  ansible.builtin.shell: |
    for i in $(seq 1 60); do
      c=$(ctdb ip | awk -v me="$(hostname -I | awk '{print $1}')" \
          '{ n = $NF; sub(":","",n); if (n == me) c++ } END { print c+0 }')
      [ "$c" -eq 0 ] && exit 0
      sleep 5
    done
    echo "VIP encore portées:"; ctdb ip; exit 1
  register: drain_vip
  until: drain_vip.rc == 0
  retries: 3
  delay: 10
  changed_when: false

- name: Attendre zéro client NFS et zéro verrou v3
  ansible.builtin.shell: |
    end=$(( $(date +%s) + {{ client_timeout }} ))
    while [ $(date +%s) -lt $end ]; do
      if [ -d /proc/fs/nfsd/clients ]; then
        c=$(find /proc/fs/nfsd/clients -mindepth 1 -maxdepth 1 -type d | wc -l)
      else
        c=$(ss -tH state established '( sport = :2049 )' 2>/dev/null | wc -l)
      fi
      v=$(find /var/lib/nfs/sm -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
      [ "$c" -eq 0 ] && [ "$v" -eq 0 ] && exit 0
      sleep {{ poll_interval }}
    done
    echo "clients=$c verrous_v3=$v"
    showmount -a localhost 2>/dev/null || true
    exit 1
  changed_when: false

- name: Arrêter les services NFS locaux
  ansible.builtin.systemd:
    name: "{{ item }}"
    state: stopped
  loop: "{{ nfs_services_stop }}"
```

### `tasks/upgrade.yaml`

```yaml
---
- name: Marquer le nœud en maintenance
  ansible.builtin.file:
    path: /var/run/ctdb-upgrade-maintenance
    state: touch
    mode: '0644'

- name: Mettre à jour les paquets OS
  ansible.builtin.package:
    name: '*'
    state: latest
  register: pkg_out

- name: Détection reboot nécessaire (kernel changé)
  ansible.builtin.shell: |
    if command -v needs-restarting >/dev/null; then
      needs-restarting -r >/dev/null 2>&1 && echo no || echo yes
    else
      rpm -q kernel | grep -q "$(uname -r)" && echo no || echo yes
    fi
  register: needs_reboot
  changed_when: false

- name: Reboot (le nœud reste DISABLED côté ctdb : il ne prendra pas les VIP)
  ansible.builtin.reboot:
    reboot_timeout: 1800
    post_reboot_delay: 30
  when: reboot_if_kernel_updated | bool and needs_reboot.stdout == "yes"
```

⚠️ Le reboot fait repartir `ctdbd` avec le nœud toujours **DISABLED** (état persisté — voulu).
On ne réactive RIEN automatiquement avant `resume`.

### `tasks/resume.yaml`

```yaml
---
- name: Démarrer les services NFS (rpcbind d'abord)
  ansible.builtin.systemd:
    name: "{{ item }}"
    state: started
    enabled: true
  loop: "{{ nfs_services_start }}"

- name: Sanity — NFSD répond sur localhost (v4)
  ansible.builtin.command: "rpcinfo -t localhost nfs 4"
  changed_when: false

- name: Nettoyer le marqueur de maintenance
  ansible.builtin.file:
    path: /var/run/ctdb-upgrade-maintenance
    state: absent

- name: Re-enable ctdb
  ansible.builtin.command: ctdb enable

- name: Attendre le nœud OK
  ansible.builtin.command: ctdb nodestatus
  register: ctdb_st
  until: "'OK' in ctdb_st.stdout"
  retries: 30
  delay: 5
  changed_when: false

- name: Rapport — état cluster + distribution VIP
  ansible.builtin.command: "ctdb -n all status && ctdb ip"
  register: report
  changed_when: false

- name: Rapport
  ansible.builtin.debug:
    msg: "{{ report.stdout }}"
```

### `tasks/verify.yaml`

```yaml
---
- name: Test montage NFS sur une VIP
  ansible.builtin.shell: |
    mkdir -p /mnt/ctdb-verify
    mount -t nfs -o ro,soft,retrans=2,timeo=10 {{ verify_host }}:{{ verify_export }} /mnt/ctdb-verify
    ls /mnt/ctdb-verify >/dev/null && umount /mnt/ctdb-verify && echo "VERIFY OK"
  register: verify
  changed_when: false
  failed_when: verify.stdout != "VERIFY OK"

- name: OK
  ansible.builtin.debug:
    msg: "Nœud {{ ansible_host }} upgrade OK, réintégré au cluster."
```

---

## 5. Intégration AWX

1. **Projet** : repo Git contenant `playbook.yaml` + le role.
2. **Job Template** `CTDB-Rolling-Upgrade` :
   - `serial: 1` (déjà dans le playbook)
   - **Survey** avec :
     - `upgrade_confirm` — checkbox obligatoire ("J'ai validé le runbook de maintenance")
     - optionnel : `drain_timeout`, `client_timeout`
   - **Credentials machine** + `become`.
3. **Workflow** recommandé :

```
[Pré-checks global] ─► [Upgrade Nœud A] ─► [Approval: continuer ?] ─► [Upgrade Nœud B] ─► [Post-verify global]
```

- L'**approval node** permet d'observer le cluster entre les 2 nœuds avant d'enchaîner.
- En cas d'échec sur un nœud, relancer avec **Limit** = ce nœud uniquement (le job est
  idempotent : si le nœud est déjà DISABLED, le drain est no-op et on repart proprement).

---

## 6. Points de vigilance

- **Jamais les 2 nœuds en même temps** ; `ctdb enable` seulement si l'autre nœud est OK.
- Après **reboot**, CTDB retrouve l'état *disabled* persisté — c'est normal, l'`enable`
  est fait explicitement en phase `resume`.
- En cas d'échec du drain (VIP non libérées, clients récalcitrants) :
  inspecter `ctdb status`, `ctdb ip`, `showmount -a localhost`,
  `ss -tunap | grep 2049` — ne pas rebooter "quand même".
- **NFSv3** : le failover de `statd`/`lockd` est géré par l'event script CTDB `60.nfs` ;
  `/var/lib/nfs/sm` vide = plus de verrou à récupérer.
- **nfs-ganesha** (GPFS/Lustre...) : remplacer `nfs-server` par `nfs-ganesha` dans les listes
  de services et adapter l'event script 60.nfs.
- Post-enable, vérifier l'**ip takeover** : `ctdb ip` doit montrer les VIP redéistribuées
  (`ctdb moveip <ip> <nodenum>` ou `ctdb recover` sinon).
- Valider avant de sortir : montage `mount -o nfsvers=4.2 <vip>:/export /mnt/test` depuis un client.