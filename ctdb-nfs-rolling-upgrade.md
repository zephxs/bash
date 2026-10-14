# Mise à jour rolling d'un cluster CTDB/NFS

> Runbook + scripts + playbook Ansible pour mettre à jour un nœud d'un cluster CTDB/NFS
> en s'assurant qu'il est **passif** (drain complet) avant l'upgrade.
>
> ⚠️ Corrigé par rapport à la première version : coquille dans la boucle d'attente du script shell (ligne parasite `ctdb log ...`), remplacée par un `done` propre.
>
> ⚠️ **Revue V2** — bugs critiques corrigés : assert precheck inversée, comptage VIP
> no-op (pnn comparé à une IP), `command` + `&&` (pas de shell), détection reboot
> toujours "no". Ajouts : contrôle des peers **avant** `ctdb enable`, parsing ctdb
> robuste (marqueur `THIS NODE`), `drain_timeout` réellement utilisé, garde-fou
> concurrency AWX.

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
#                                 1. contrôle que les peers sont sains
#                                 2. redémarre les services NFS
#                                 3. ctdb enable (takeover des VIP possibles)
#                                 4. vérifie l'état du cluster + test montage
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
    # Marqueur THIS NODE : stable quel que soit le format de sortie de ctdb
    # (pnn:0 ou 0:), sans dépendre de l'ordre des IP de hostname -I.
    node="$($CTDB_BIN nodestatus | grep 'THIS NODE' | awk '{sub(":","",$1); print $1}')"
    [ -n "$node" ] || die "impossible de résoudre le nœud local (pas de marqueur THIS NODE)"
    echo "$node"
}

# Nœuds peers (tous sauf nous)
get_other_nodes() {
    "$CTDB_BIN" -n all status | awk -v self="$SELF_NODE" \
        '($1 ~ /^[0-9]+:$/) { sub(":","",$1); if ($1 != self) print $1 }'
}

# VIP actuellement portées par le nœud local
local_vip_count() {
    # $NF est le pnn du porteur : "0", "pnn:0" ou "node[0]" selon la version
    "$CTDB_BIN" ip | awk -v self="$SELF_NODE" \
        '{ n = $NF; sub(":","",n); sub(/^node\[/,"",n); sub(/\]$/,"",n);
           if (n == self) c++ } END { print c+0 }'
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
    log "Contrôle de santé du cluster (peer nodes)"
    local bad=0
    while read -r -u 3 n; do
        # état extrait par mot-clé : robuste quel que soit le format de sortie
        # (awk '{print $2}' risquait de renvoyer le PID, pas l'état)
        state="$($CTDB_BIN -n "$n" nodestatus | grep -owE \
            'OK|DISABLED|UNHEALTHY|BANNED|STOPPED|DISCONNECTED' | head -1)"
        if [ "$state" != "OK" ] && [ "$state" != "DISABLED" ]; then
            log "     NŒUD $n : état '$state' -> NON OK pour maintenance"
            bad=1
        else
            log "     NŒUD $n : $state"
        fi
    done 3< <(get_other_nodes)
    [ "$bad" -eq 0 ] || die "un nœud peer n'est pas sain, ABORT"
    log "     Ce nœud: état '$($CTDB_BIN nodestatus | grep -owE \
        'OK|DISABLED|UNHEALTHY|BANNED|STOPPED|DISCONNECTED' | head -1)'"
}

do_drain() {
    if ! mkdir "$LOCKFILE" 2>/dev/null; then
        die "un drain est déjà en cours (lock: $LOCKFILE)"
    fi
    trap 'rmdir "$LOCKFILE" 2>/dev/null' EXIT

    precheck

    log "1/4  Drain : ctdb disable -n $SELF_NODE"
    "$CTDB_BIN" disable -n "$SELF_NODE" || die "disable a échoué"

    log "2/4  Attente libération des IP publiques (timeout ${DRAIN_TIMEOUT}s)"
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

    log "3/4  Attente fin des clients NFS (timeout ${CLIENT_TIMEOUT}s)"
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

    log "4/4  Arrêt des services NFS locaux, le nœud est PASSIF"
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

    log "1/5  Contrôle santé des peers (règle d'or : enable seulement si l'autre est OK)"
    precheck

    log "2/5  Redémarrage des services NFS (rpcbind d'abord)"
    # ordre inverse du drain : on parcourt NFS_SERVICES à l'envers
    for ((i=${#NFS_SERVICES[@]}-1; i>=0; i--)); do
        svc="${NFS_SERVICES[i]}"
        systemctl start "$svc" && log "     started $svc" || die "start $svc a échoué"
    done
    rpcinfo -t localhost nfs 4 >/dev/null 2>&1 || die "nfs v4 ne répond pas sur localhost"

    log "3/5  ctdb enable -n $SELF_NODE"
    "$CTDB_BIN" enable -n "$SELF_NODE" || die "ctdb enable a échoué"

    log "4/5  Attente stabilité du cluster"
    sleep 10
    while [ "$($CTDB_BIN nodestatus | grep -owE \
        'OK|DISABLED|UNHEALTHY|BANNED|STOPPED|DISCONNECTED' | head -1)" != "OK" ]; do
        sleep 5; log "     nœud pas encore OK, attente..."
    done
    "$CTDB_BIN" -n all status | sed 's/^/     /'

    log "5/5  Distribution des VIP après takeover"
    "$CTDB_BIN" ip | sed 's/^/     /'
    rm -f /var/run/ctdb-upgrade-drain.done

    log "NŒUD ACTIF À NOUVEAU — valider un montage client sur une VIP avant de sortir."
}

usage() {
    # Affiche le bloc de commentaires d'en-tête — robuste aux éditions du script
    # (un sed '2,32p' fixe cassait au moindre ajout de ligne)
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
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
├── inventory.ini             # [nfs_cluster] node1 node2 (syntaxe INI)
├── playbook.yaml
└── roles/ctdb-rolling-upgrade/
    ├── defaults/main.yaml
    └── tasks/
        ├── main.yaml
        ├── precheck.yaml
        ├── drain.yaml
        ├── upgrade.yaml
        ├── resume.yaml
        └── verify.yaml
```

### `inventory.ini`

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

### `tasks/main.yaml`

```yaml
---
- name: Pré-vérifications cluster
  ansible.builtin.include_tasks: precheck.yaml

- name: Drain du nœud (disable + attente clients)
  ansible.builtin.include_tasks: drain.yaml

- name: Upgrade paquets + reboot éventuel
  ansible.builtin.include_tasks: upgrade.yaml

- name: Reprise de service
  ansible.builtin.include_tasks: resume.yaml

- name: Vérification finale
  ansible.builtin.include_tasks: verify.yaml
```

> `include_tasks` plutôt qu'`import_tasks` : chaque phase est un bloc log ;
> avec `serial: 1` + `any_errors_fatal`, un include au milieu de la boucle garde
> le comportement d'abort par hôte voulu.

### `tasks/precheck.yaml`

```yaml
---
- name: Statut de tous les nœuds ctdb
  ansible.builtin.command: ctdb -n all status
  register: ctdb_status_all
  changed_when: false

- name: Vérifier qu'aucun nœud n'est dans un état non sain
  # Recherche texte sur la sortie complète : robuste quel que soit le format
  # de sortie de ctdb (pnn:0 ou 0:). DISABLED n'est PAS interdit
  # (idempotence : rerun possible sur un nœud déjà drainé).
  ansible.builtin.assert:
    that:
      - ctdb_status_all.stdout is not search(item)
    fail_msg: "État '{{ item }}' détecté — ABORT :\n{{ ctdb_status_all.stdout }}"
  loop:
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

- name: Attendre 0 VIP portée par le nœud (timeout drain_timeout)
  # pnn local via le marqueur THIS NODE (stable toutes versions de ctdb),
  # puis comparaison pnn ↔ pnn — JAMAIS pnn ↔ adresse IP.
  # Pas de until/retries : un seul timeout, piloté par {{ drain_timeout }}.
  ansible.builtin.shell: |
    me="$(ctdb nodestatus | grep 'THIS NODE' | awk '{sub(":","",$1); print $1}')"
    [ -n "$me" ] || { echo "pnn local introuvable (pas de marqueur THIS NODE)"; exit 1; }
    end=$(( $(date +%s) + {{ drain_timeout }} ))
    while [ "$(date +%s)" -lt "$end" ]; do
      c=$(ctdb ip | awk -v me="$me" \
          '{ n = $NF; sub(":","",n); sub(/^node\[/,"",n); sub(/\]$/,"",n);
             if (n == me) c++ } END { print c+0 }')
      [ "$c" -eq 0 ] && exit 0
      sleep {{ poll_interval }}
    done
    echo "VIP encore portées:"; ctdb ip; exit 1
  register: drain_vip
  changed_when: false

- name: Attendre zéro client NFS et zéro verrou v3
  ansible.builtin.shell: |
    end=$(( $(date +%s) + {{ client_timeout }} ))
    while [ $(date +%s) -lt $end ]; do
      if [ -d /proc/fs/nfsd/clients ]; then
        c=$(find /proc/fs/nfsd/clients -mindepth 1 -maxdepth 1 -type d | wc -l)
      else
        c=$(ss -tH state established '( sport = :2049 or dport = :2049 )' 2>/dev/null | wc -l)
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
  # 'name: "*"' fonctionne avec dnf/yum (RHEL-like).
  # Sur Debian : remplacer par le module apt avec "upgrade: dist".
  ansible.builtin.package:
    name: '*'
    state: latest
  register: pkg_out

- name: Détection reboot nécessaire (kernel changé)
  ansible.builtin.shell: |
    if command -v needs-restarting >/dev/null; then
      needs-restarting -r >/dev/null 2>&1 && echo no || echo yes
    else
      # fallback : le kernel EN COURS doit être le plus RÉCENT installé.
      # (l'ancien kernel reste installé — un simple grep "$(uname -r)"
      #  matcherait toujours et ne détecterait jamais le reboot)
      latest="$(rpm -q kernel | sort -V | tail -1 | sed 's/^kernel-//')"
      [ "$(uname -r)" = "$latest" ] && echo no || echo yes
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
- name: Contrôle santé des peers avant enable
  # Règle d'or (§2/§6) : on ne réactive QUE si l'autre nœud est sain.
  # DISABLED (soi-même) n'est pas interdit.
  ansible.builtin.command: ctdb -n all status
  register: ctdb_status_all_resume
  changed_when: false

- name: Refuser l'enable si un nœud est dans un état non sain
  ansible.builtin.assert:
    that:
      - ctdb_status_all_resume.stdout is not search(item)
    fail_msg: "Peer non sain — enable refusé :\n{{ ctdb_status_all_resume.stdout }}"
  loop:
    - 'UNHEALTHY'
    - 'DISCONNECTED'
    - 'BANNED'
    - 'STOPPED'

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
  # shell (pas command) : "&&" exige un shell
  ansible.builtin.shell: "ctdb -n all status && ctdb ip"
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

> ⚠️ Ce test tourne **sur le nœud upgradé lui-même** : s'il a déjà repris une VIP,
> le montage peut être servi localement et ne teste pas la bascule. Pour un vrai
> test de reprise, l'exécuter depuis une machine témoin
> (`delegate_to: <client-témoin>` sur la tâche de montage), cf. §6.

---

## 5. Intégration AWX

1. **Projet** : repo Git contenant `playbook.yaml` + le role.
2. **Job Template** `CTDB-Rolling-Upgrade` :
   - `serial: 1` (déjà dans le playbook)
   - **Survey** avec :
     - `upgrade_confirm` — checkbox obligatoire ("J'ai validé le runbook de maintenance")
     - optionnel : `drain_timeout`, `client_timeout`
   - **Credentials machine** + `become`.
   - **Concurrency limit : 1** — sinon deux jobs lancés en parallèle draineraient
     les 2 nœuds en même temps (`serial: 1` ne protège qu'à l'intérieur d'UN job).
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