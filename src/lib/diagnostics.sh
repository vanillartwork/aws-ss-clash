#!/usr/bin/env bash
# RayLink diagnostics: `raylink doctor` (read-only health/drift report) and
# `raylink info` (node summary). Both run in a role's context (exit or relay),
# which the dispatcher auto-detects.

# Detect which node role is installed on this host (default paths).
detect_installed_role() {
  if [ -f /etc/raylink-exit-healthcheck.env ] || [ -f /opt/cloud-xray-exit/reality.env ]; then
    echo exit; return 0
  fi
  if [ -f /etc/raylink-relay-healthcheck.env ] || [ -f /opt/cloud-xray-relay/reality.env ]; then
    echo relay; return 0
  fi
  return 1
}

# Resilient public-IP detection for diagnostics: sets PUBLIC_IP / PUBLIC_IP_FAMILY
# and the auto IPv6 LISTEN_ADDRESS, but never exits (unlike the install path).
_dr_detect() {
  local ver
  ver="$(printf '%s' "${PUBLIC_IP_VERSION:-auto}" | tr '[:upper:]' '[:lower:]')"
  DR_HOST_OVERRIDE=""
  if [ -n "${PUBLIC_HOST:-}" ] && valid_domain "${PUBLIC_HOST}"; then
    DR_HOST_OVERRIDE=1
  fi
  if [ -n "${PUBLIC_IP:-}" ]; then
    if valid_public_ipv4 "${PUBLIC_IP}"; then PUBLIC_IP_FAMILY=4
    elif valid_public_ipv6 "${PUBLIC_IP}"; then PUBLIC_IP_FAMILY=6; fi
  else
    case "${ver}" in
      4|ipv4|v4) PUBLIC_IP="$(detect_public_ipv4 || true)"; PUBLIC_IP_FAMILY=4 ;;
      6|ipv6|v6) PUBLIC_IP="$(detect_public_ipv6 || true)"; PUBLIC_IP_FAMILY=6 ;;
      *)
        if PUBLIC_IP="$(detect_public_ipv4)"; then PUBLIC_IP_FAMILY=4
        elif PUBLIC_IP="$(detect_public_ipv6)"; then PUBLIC_IP_FAMILY=6
        else
          PUBLIC_IP=""
          if [ -n "${DR_HOST_OVERRIDE}" ]; then
            case "${ver}" in 6|ipv6|v6) PUBLIC_IP_FAMILY=6 ;; *) PUBLIC_IP_FAMILY=4 ;; esac
          fi
        fi
        ;;
    esac
  fi
  if [ -z "${LISTEN_ADDRESS_WAS_SET:-}" ] && [ "${PUBLIC_IP_FAMILY:-4}" = 6 ]; then
    LISTEN_ADDRESS="::"
  fi
}

_dr_port_listening() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\.)${1}\$"
}

# ---- doctor output helpers ----
DR_FAIL=0
_ok()   { printf '  \xe2\x9c\x93 %s\n' "$*"; }
_fail() { printf '  \xe2\x9c\x97 %s\n' "$*"; DR_FAIL=1; }
_warn() { printf '  ! %s\n' "$*"; }
_fix()  { printf '      Fix: %s\n' "$*"; }

# Config drift: re-render the config from saved state to a temp file and compare
# it byte-for-byte with the live config. Report only — never overwrites.
_dr_config_drift() {
  [ -f "${XRAY_CONFIG}" ] || return 0
  if [ ! -f "${REALITY_ENV_FILE}" ]; then
    _warn "Config integrity: cannot verify (reality.env missing)"; return 0
  fi
  if ! load_existing_reality_credentials_for_healthcheck >/dev/null 2>&1; then
    _warn "Config integrity: cannot verify (incomplete saved credentials)"; return 0
  fi
  if [ -n "${UPSTREAM_ENV_FILE:-}" ] && [ -f "${UPSTREAM_ENV_FILE}" ]; then
    _load_saved_upstream; _apply_upstream_defaults
  fi
  local tmp; tmp="$(mktemp)"
  if ! "${XRAY_CONFIG_RENDERER:-render_exit_xray_config}" "${tmp}" 2>/dev/null; then
    _warn "Config integrity: cannot verify (render failed)"; rm -f "${tmp}"; return 0
  fi
  if cmp -s "${tmp}" "${XRAY_CONFIG}"; then
    _ok "Config integrity: matches RayLink-generated config"
  else
    _fail "Config drift detected: ${XRAY_CONFIG} differs from RayLink's generated config"
    _fix "sudo raylink ${RAYLINK_COMMAND}   (regenerates config — this OVERWRITES manual edits)"
  fi
  rm -f "${tmp}"
}

run_doctor() {
  require_root
  echo "RayLink ${RAYLINK_VERSION:-} — ${NODE_ROLE} node doctor"
  echo ""
  DR_FAIL=0

  # Xray binary + service
  if [ -x "${XRAY_BIN}" ]; then _ok "Xray installed (${XRAY_BIN})"
  else _fail "Xray binary missing at ${XRAY_BIN}"; _fix "sudo raylink ${RAYLINK_COMMAND}"; fi

  if systemctl is-active --quiet "${XRAY_SERVICE}"; then _ok "Xray service active (${XRAY_SERVICE})"
  else _fail "Xray service not running"; _fix "sudo systemctl start ${XRAY_SERVICE}"; fi

  if systemctl is-enabled --quiet "${XRAY_SERVICE}" 2>/dev/null; then _ok "Xray enabled at boot"
  else _warn "Xray not enabled at boot"; _fix "sudo systemctl enable ${XRAY_SERVICE}"; fi

  # Node port
  if _dr_port_listening "${PORT}"; then _ok "Node port ${PORT} listening"
  else _fail "Node port ${PORT} not listening"; _fix "sudo journalctl -u ${XRAY_SERVICE} -n 50"; fi

  # Subscription
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    if systemctl is-active --quiet nginx; then _ok "nginx active"
    else _fail "nginx not running"; _fix "sudo systemctl start nginx"; fi
    if _dr_port_listening "${SUB_PORT}"; then _ok "Subscription port ${SUB_PORT} listening"
    else _fail "Subscription port ${SUB_PORT} not listening"; fi
  else
    _ok "Subscription disabled (skipped)"
  fi

  # Health check timer
  if is_true "${ENABLE_HEALTHCHECK_TIMER}"; then
    if systemctl is-active --quiet "${HEALTHCHECK_TIMER_NAME}"; then _ok "Health check timer active (${HEALTHCHECK_TIMER_NAME})"
    else _warn "Health check timer not active"; _fix "sudo systemctl enable --now ${HEALTHCHECK_TIMER_NAME}"; fi
  fi

  # Config present
  if [ -f "${XRAY_CONFIG}" ]; then _ok "Xray config present"
  else _fail "Xray config missing (${XRAY_CONFIG})"; _fix "sudo raylink ${RAYLINK_COMMAND}"; fi

  # Public IP / host
  _dr_detect
  if [ -n "${DR_HOST_OVERRIDE}" ]; then
    _ok "Client host: ${PUBLIC_HOST} (server IPv${PUBLIC_IP_FAMILY:-?}, ${PUBLIC_IP:-no IP})"
  elif [ -n "${PUBLIC_IP:-}" ]; then
    _ok "Public IP: ${PUBLIC_IP} (IPv${PUBLIC_IP_FAMILY})"
  else
    _fail "Could not detect a public IP"; _fix "set PUBLIC_IP=... or PUBLIC_HOST=..., or check connectivity"
  fi

  # Config drift (re-render + compare)
  _dr_config_drift

  # Reality self-test (needs xray running + creds)
  if [ -f "${REALITY_ENV_FILE}" ] && systemctl is-active --quiet "${XRAY_SERVICE}"; then
    if run_reality_self_test_once >/dev/null 2>&1; then _ok "Reality self-test passed (end-to-end)"
    else _fail "Reality self-test failed"; _fix "sudo raylink ${RAYLINK_COMMAND} --health-check"; fi
  fi

  echo ""
  if [ "${DR_FAIL}" -eq 0 ]; then echo "All checks passed."; else echo "Some checks failed — see the Fix hints above."; fi
  return "${DR_FAIL}"
}

# ---- info ----
_info_secret() { [ "${SHOW_SECRETS:-false}" = true ] && printf '%s' "$1" || printf '<hidden>'; }
_info_url() {
  local url="$1" tok="$2"
  if [ "${SHOW_SECRETS:-false}" = true ] || [ -z "${tok}" ]; then printf '%s' "${url}"
  else printf '%s' "${url//${tok}/<TOKEN>}"; fi
}

run_info() {
  require_root
  local uuid sub_uni sub_clash sub_token upstream_addr upstream_port
  uuid="$(load_kv_file_var "${REALITY_ENV_FILE}" UUID)"
  if [ -f "${SUB_ENV_FILE}" ]; then
    sub_uni="$(load_kv_file_var "${SUB_ENV_FILE}" SUBSCRIPTION_URL_UNIVERSAL)"
    sub_clash="$(load_kv_file_var "${SUB_ENV_FILE}" SUBSCRIPTION_URL_CLASH)"
    sub_token="$(load_kv_file_var "${SUB_ENV_FILE}" SUB_TOKEN)"
  fi
  _dr_detect

  printf 'RayLink %s\n' "${RAYLINK_VERSION:-}"
  printf 'Role:           %s\n' "${NODE_ROLE}"
  printf 'Install dir:    %s\n' "${INSTALL_DIR}"
  printf 'Xray service:   %s (%s)\n' "${XRAY_SERVICE}" "$(systemctl is-active "${XRAY_SERVICE}" 2>/dev/null || echo inactive)"
  if is_true "${ENABLE_HEALTHCHECK_TIMER}"; then
    printf 'Health timer:   %s (%s)\n' "${HEALTHCHECK_TIMER_NAME}" "$(systemctl is-active "${HEALTHCHECK_TIMER_NAME}" 2>/dev/null || echo inactive)"
  fi
  printf 'Node port:      %s/tcp\n' "${PORT}"
  [ -n "${PUBLIC_HOST:-}" ] && printf 'Public host:    %s\n' "${PUBLIC_HOST}"
  printf 'Public IP:      %s\n' "${PUBLIC_IP:-<not detected>}"
  if [ -n "${UPSTREAM_ENV_FILE:-}" ] && [ -f "${UPSTREAM_ENV_FILE}" ]; then
    upstream_addr="$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_ADDRESS)"
    upstream_port="$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_PORT)"
    printf 'Upstream exit:  %s:%s\n' "${upstream_addr}" "${upstream_port}"
  fi
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    printf 'Subscription:   enabled (port %s)\n' "${SUB_PORT}"
    printf 'Universal URL:  %s\n' "$(_info_url "${sub_uni}" "${sub_token}")"
    printf 'Clash URL:      %s\n' "$(_info_url "${sub_clash}" "${sub_token}")"
  else
    printf 'Subscription:   disabled\n'
  fi
  printf 'UUID:           %s\n' "$(_info_secret "${uuid}")"

  if [ "${SHOW_SECRETS:-false}" != true ]; then
    echo ""
    echo "(secrets hidden — pass --show-secrets to reveal, or see ${INFO_FILE})"
  fi
}
