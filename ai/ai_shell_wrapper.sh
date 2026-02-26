#!/usr/bin/env bash
# /usr/local/bin/ai-shell-wrapper
# Version 2026-02 – Bastion IA logging + restrictions modérées
# Licence: utilise librement, mais garde les logs intacts svp.

set -euo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION – À ADAPTER SELON TON RISQUE / BESOINS
# ──────────────────────────────────────────────────────────────────────────────

readonly LOG_BASE="/var/log/ai-sessions"
readonly MAX_SESSION_DURATION=1800          # 30 min max par session
readonly MAX_COMMANDS_PER_MIN=120           # burst protection basique

# Commandes explicitement interdites (même via /bin/sh -c, exec, etc.)
readonly BLACKLIST_PATTERNS=(
    '^rm[[:space:]]+-rf[[:space:]]+/*'
    '^dd[[:space:]]+if='
    '^mkfs'
    '^chmod[[:space:]]+777'
    '^chown[[:space:]]+root'
    '^sudo'
    '^su'
    '^passwd'
    '^reboot'
    '^poweroff'
    '^halt'
    '^systemctl.*(start|stop|restart).*'
    '^curl.*http'
    '^wget'
    '^nc[[:space:]]+-e'          # reverse shell classique
    '^bash[[:space:]]+-i'
    '^python[[:space:]]+-c.*(socket|os.system)'
)

# Whitelist optionnel (si activé, tout le reste est interdit)
# readonly ALLOWED_COMMANDS_ONLY=true
readonly ALLOWED_COMMANDS_ONLY=false

# Commandes autorisées si ALLOWED_COMMANDS_ONLY=true
readonly WHITELIST=(
    "uptime" "hostname" "whoami" "id" "pwd" "ls" "cat" "tail" "head" "grep"
    "find" "df" "du" "free" "top" "ps" "netstat" "ss" "ip" "ifconfig"
    "dmesg" "journalctl" "systemctl status"   # lecture seule
    # Ajoute ici les commandes safe que ton agent Codex doit pouvoir lancer
)

# ──────────────────────────────────────────────────────────────────────────────
# NE PAS TOUCHER EN DESSOUS SAUF SI TU SAIS CE QUE TU FAIS
# ──────────────────────────────────────────────────────────────────────────────

readonly SESSION_USER="\( {USER:- \)(whoami)}"
readonly SESSION_IP="${SSH_CLIENT%% *}"
readonly SESSION_TS="$(date --iso-8601=seconds)"
readonly SESSION_ID="\( {SESSION_TS//:/-}- \){BASHPID}-${SESSION_IP//./-}"

readonly LOG_DIR="\( {LOG_BASE}/ \)(date +%Y-%m)"
readonly TS_FILE="\( {LOG_DIR}/session- \){SESSION_ID}.timing"
readonly LOG_FILE="\( {LOG_DIR}/session- \){SESSION_ID}.typescript"
readonly AUDIT_FILE="\( {LOG_DIR}/index- \){SESSION_TS:0:10}.log"

mkdir -p "${LOG_DIR}" || { echo "ERREUR: impossible de créer ${LOG_DIR}" >&2; exit 1; }
chmod 750 "${LOG_DIR}"
chown root:ai-admins "${LOG_DIR}"  # adapte au groupe qui doit lire les logs

# Petit banner + infos session (facilite l’audit humain)
{
    echo "═══════════════════════════════════════════════════════════════"
    echo "Session AI démarrée le ${SESSION_TS}"
    echo "Utilisateur : ${SESSION_USER}"
    echo "IP source   : ${SESSION_IP}"
    echo "PID         : ${BASHPID}"
    echo "═══════════════════════════════════════════════════════════════"
} >> "${LOG_FILE}"

# Logging index global
echo "${SESSION_TS} | ${SESSION_USER} | \( {SESSION_IP} | session- \){SESSION_ID}" >> "${AUDIT_FILE}"

# Protection basique contre DoS / boucle infinie de l’IA
(
    sleep "${MAX_SESSION_DURATION}"
    echo "Session expirée (durée max \( {MAX_SESSION_DURATION}s)" >> " \){LOG_FILE}"
    pkill -P "${BASHPID}"  # tue les enfants mais pas le wrapper lui-même
) &  # background watchdog

# Fonction de filtrage des commandes
function is_command_forbidden() {
    local cmd="$1"

    # Blacklist pattern matching
    for pat in "${BLACKLIST_PATTERNS[@]}"; do
        if [[ ${cmd} =\~ ${pat} ]]; then
            echo "COMMAND REJECTED: matched blacklist '${pat}'" >&2
            echo "BLOCKED: \( {cmd}" >> " \){LOG_FILE}"
            return 0  # forbidden → true
        fi
    done

    if ${ALLOWED_COMMANDS_ONLY:-false}; then
        for allowed in "${WHITELIST[@]}"; do
            if [[ "\( {cmd}" == " \){allowed}" || "\( {cmd}" =\~ ^ \){allowed}[[:space:]] ]]; then
                return 1  # allowed
            fi
        done
        echo "COMMAND REJECTED: not in whitelist" >&2
        echo "BLOCKED (whitelist): \( {cmd}" >> " \){LOG_FILE}"
        return 0
    fi

    return 1  # par défaut on laisse passer si pas blacklisted
}

# Trap pour logger la fin de session
trap '
    echo "═══════════════════════════════════════════════════════════════" >> "${LOG_FILE}"
    echo "Session terminée à \( (date --iso-8601=seconds)" >> " \){LOG_FILE}"
    echo "═══════════════════════════════════════════════════════════════" >> "${LOG_FILE}"
' EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Boucle principale – shell interactif avec logging
# ──────────────────────────────────────────────────────────────────────────────

echo "Bienvenue sur le bastion IA – toutes les actions sont enregistrées." >&2
echo "Utilise 'exit' pour quitter proprement." >&2

# On lance script(1) pour capturer TOUT (y compris vim, less, etc.)
# --flush pour éviter de perdre des logs en cas de crash
exec script \
    --timing="${TS_FILE}" \
    --flush \
    --quiet \
    --command \
    "
        # On force un shell login propre
        export PS1='[AI-BASTION \u@\h \W]\$ '
        export PATH='/usr/local/ai-safebin:/usr/bin:/bin'  # PATH très limité !

        while true; do
            # On lit la ligne (read -r pour ne pas interpréter les backslashes)
            read -r -e -p '\$ ' cmd || break

            # On logge la commande brute AVANT exécution
            echo \"[\$(date +%H:%M:%S)] \\( cmd\" >> \" \){LOG_FILE}\"

            # Filtrage
            if is_command_forbidden \"\$cmd\"; then
                echo 'Commande refusée par politique de sécurité.' >&2
                continue
            fi

            # Exécution (dans un sous-shell pour limiter les dégâts)
            (
                set -e
                eval \"\$cmd\"
            ) 2>&1 | tee -a \"${LOG_FILE}\"

            # Petit délai anti-flood
            (( cmd_count++ ))
            if (( cmd_count % 10 == 0 )); then
                sleep 0.1
            fi
        done
    " \
    "${LOG_FILE}"

# Si on arrive ici → sortie anormale
echo "Session terminée de façon inattendue" >> "${LOG_FILE}"
exit 1

