#!/usr/bin/env bash
# RayLink exit command: full install and lightweight health check.
# Orchestration only; reusable logic lives in lib/*.sh
# (validate_common_ports -> common.sh, detect_public_ip_and_resolve_dns -> dns.sh).

run_healthcheck_mode() {
  require_root

  if [ -z "${ENABLE_SUBSCRIPTION_WAS_SET}" ] && [ ! -f "${SUB_ENV_FILE}" ]; then
    ENABLE_SUBSCRIPTION="false"
  fi

  validate_common_ports

  echo "=========================================="
  echo " RayLink exit health check"
  echo "=========================================="

  if [ ! -x "${XRAY_BIN}" ]; then
    echo "Error: Xray binary not found at ${XRAY_BIN}. Run the full installer first."
    exit 1
  fi

  mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"
  detect_public_ip_and_resolve_dns
  load_existing_reality_credentials_for_healthcheck
  validate_reality_inputs
  ensure_xray_running_for_healthcheck

  perform_reality_self_test_with_fallbacks
  sync_client_outputs

  echo "Health check complete. Client files and subscription data are up to date."
  echo "Current public IP: ${PUBLIC_IP:-<not detected>}"
  # Do not echo the token-bearing subscription URL: this runs under systemd and
  # its output is persisted to journald. The full URLs live in ${INFO_FILE}.
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Subscription files regenerated (URLs saved in ${INFO_FILE})."
  fi
}

run_full_install() {
  require_root
  validate_common_ports

  echo "=========================================="
  echo " Xray VLESS Reality Generic Exit Setup"
  echo "=========================================="

  echo "[1/12] Installing required packages..."
  install_required_packages

  echo "[2/12] Applying TCP tuning..."
  apply_tcp_tuning

  echo "[3/12] Preparing directories..."
  mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"

  echo "[4/12] Detecting public IPv4 and selecting DNS profile..."
  detect_public_ip_and_resolve_dns

  echo "[5/12] Stopping old services that may occupy the exit port..."
  systemctl disable --now shadowsocks-libev >/dev/null 2>&1 || true
  systemctl disable --now shadowsocks-libev-server@config.service >/dev/null 2>&1 || true
  systemctl stop "${XRAY_SERVICE}" >/dev/null 2>&1 || true

  echo "[6/12] Installing Xray-core..."
  install_xray

  echo "[7/12] Loading or generating VLESS/Reality credentials..."
  load_or_generate_reality_credentials

  echo "[8/12] Checking Reality target..."
  check_reality_target

  echo "[9/12] Writing Xray config and systemd service..."
  ensure_xray_service_identity
  validate_reality_inputs
  write_xray_config
  write_xray_service

  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG}"

  systemctl daemon-reload
  systemctl enable "${XRAY_SERVICE}" >/dev/null 2>&1
  systemctl restart "${XRAY_SERVICE}"

  sleep 1

  if ! systemctl is-active --quiet "${XRAY_SERVICE}"; then
    echo "Xray failed to start."
    systemctl status "${XRAY_SERVICE}" --no-pager || true
    journalctl -u "${XRAY_SERVICE}" -n 80 --no-pager || true
    exit 1
  fi

  echo "[10/12] Running Reality self-test and fallback target selection..."
  perform_reality_self_test_with_fallbacks

  echo "[11/12] Generating Mihomo/Clash config and VLESS URI-list subscription..."
  sync_client_outputs

  echo "[12/12] Configuring periodic health check..."
  install_healthcheck_timer

  echo ""
  echo "=========================================="
  echo "Setup complete"
  echo "=========================================="
  echo "Full server information saved to: ${INFO_FILE}"

  echo ""
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Universal Subscription URL:"
    echo "    ${SUBSCRIPTION_URL_UNIVERSAL}"
    echo "Clash Subscription URL:"
    echo "    ${SUBSCRIPTION_URL_CLASH}"
  else
    echo "Direct VLESS Link:"
    echo "    ${VLESS_URI}"
  fi

  echo ""
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Important: allow inbound TCP ${PORT} and ${SUB_PORT} in your cloud firewall/security group."
  else
    echo "Important: allow inbound TCP ${PORT} in your cloud firewall/security group."
  fi
  echo "Client compatibility, service status, and troubleshooting: see the README."
}

exit_main() {
  # Capture whether ENABLE_SUBSCRIPTION / LISTEN_ADDRESS were explicitly set
  # BEFORE loading defaults (defaults assign via :=, which would mark them set).
  ENABLE_SUBSCRIPTION_WAS_SET="${ENABLE_SUBSCRIPTION+x}"
  LISTEN_ADDRESS_WAS_SET="${LISTEN_ADDRESS+x}"
  PUBLIC_IP_WAS_SET="${PUBLIC_IP+x}"

  local mode="install"
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --health-check|--healthcheck|healthcheck) mode="health" ;;
      doctor) mode="doctor" ;;
      info) mode="info" ;;
      --show-secrets) SHOW_SECRETS="true" ;;
      *)
        echo "Unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  # Load configuration defaults (env-provided values win via := assignment).
  # shellcheck source=/dev/null
  . "${RAYLINK_DEFAULTS}/exit.env"
  # shellcheck source=/dev/null
  . "${RAYLINK_DEFAULTS}/legacy.env"

  # Config-render hook (used by the doctor drift check).
  XRAY_CONFIG_RENDERER="render_exit_xray_config"

  case "${mode}" in
    health) run_healthcheck_mode ;;
    doctor|info)
      # Load install-time settings (TFO, metrics, pinned addresses) so the
      # drift comparison and info reflect how the node was actually built.
      # shellcheck source=/dev/null
      [ -f "${HEALTHCHECK_ENV_FILE}" ] && . "${HEALTHCHECK_ENV_FILE}"
      [ "${mode}" = doctor ] && run_doctor || run_info
      ;;
    *) run_full_install ;;
  esac
}
