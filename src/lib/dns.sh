#!/usr/bin/env bash
# DNS profile detection and selection for the generated Clash/Mihomo YAML.

detect_server_country_code() {
  if [ -n "${SERVER_COUNTRY:-}" ]; then
    printf '%s\n' "${SERVER_COUNTRY}" | tr '[:lower:]' '[:upper:]' | head -c 2
    return 0
  fi

  local url country
  for url in \
    "https://ipinfo.io/${PUBLIC_IP}/country" \
    "https://ipapi.co/${PUBLIC_IP}/country/" \
    "http://ip-api.com/line/${PUBLIC_IP}?fields=countryCode"; do
    country="$(curl -4 -fsS -m 6 "${url}" 2>/dev/null | tr -dc 'A-Za-z' | tr '[:lower:]' '[:upper:]' | head -c 2 || true)"
    if printf '%s' "${country}" | grep -Eq '^[A-Z]{2}$'; then
      printf '%s\n' "${country}"
      return 0
    fi
  done

  return 1
}

country_in_auto_domestic_list() {
  local country="${1:-}"
  local item
  for item in ${AUTO_DNS_DOMESTIC_COUNTRIES}; do
    if [ "${country}" = "$(printf '%s' "${item}" | tr '[:lower:]' '[:upper:]')" ]; then
      return 0
    fi
  done
  return 1
}

resolve_dns_profile() {
  local requested
  requested="$(printf '%s' "${DNS_PROFILE:-mixed}" | tr '[:upper:]' '[:lower:]')"

  case "${requested}" in
    foreign|global|world|overseas|abroad)
      DNS_EFFECTIVE_PROFILE="foreign"
      ;;
    domestic|return|home|backhome|china-home)
      DNS_EFFECTIVE_PROFILE="domestic"
      ;;
    mixed|cn|china)
      DNS_EFFECTIVE_PROFILE="mixed"
      ;;
    minimal|compat|compatible)
      DNS_EFFECTIVE_PROFILE="minimal"
      ;;
    auto)
      DNS_DETECTED_COUNTRY="$(detect_server_country_code || true)"
      if [ -n "${DNS_DETECTED_COUNTRY}" ] && country_in_auto_domestic_list "${DNS_DETECTED_COUNTRY}"; then
        DNS_EFFECTIVE_PROFILE="domestic"
      else
        DNS_EFFECTIVE_PROFILE="foreign"
      fi
      ;;
    "")
      DNS_EFFECTIVE_PROFILE="mixed"
      ;;
    *)
      echo "Unknown DNS_PROFILE=${DNS_PROFILE}. Valid values: mixed, foreign, domestic, minimal, auto."
      echo "Aliases: global/world/overseas -> foreign; return/home/backhome -> domestic; cn/china -> mixed."
      exit 1
      ;;
  esac

  if [ -z "${DNS_DETECTED_COUNTRY}" ]; then
    DNS_DETECTED_COUNTRY="not-used"
  fi

  echo "DNS profile requested: ${DNS_PROFILE}"
  echo "DNS profile selected: ${DNS_EFFECTIVE_PROFILE}"
  echo "Server country detected: ${DNS_DETECTED_COUNTRY}"
}

# Detect the public IP (IPv4 preferred) and resolve the effective DNS profile.
# Shared by the exit and relay commands.
#
# PUBLIC_IP_VERSION=auto (default): try IPv4, fall back to IPv6.
# PUBLIC_IP_VERSION=4 / 6: force a family. A user-provided PUBLIC_IP is
# validated and its family auto-detected.
#
# PUBLIC_HOST=<domain>: a hostname (e.g. a DDNS domain) used as the CLIENT-facing
# address. The server still detects its real public IP to choose the listen
# family; the domain only overrides the VLESS link / subscription / Clash server
# host so clients keep working across IP changes.
#
# Sets PUBLIC_IP_FAMILY (4/6), PUBLIC_CLASH_HOST (unbracketed, for Clash), and
# PUBLIC_URI_HOST / PUBLIC_URL_HOST (IPv6 bracketed, for URIs/URLs). With no
# override on IPv4 these all equal PUBLIC_IP, so the IPv4 path is unchanged.
detect_public_ip_and_resolve_dns() {
  local ver host_override=""
  ver="$(printf '%s' "${PUBLIC_IP_VERSION:-auto}" | tr '[:upper:]' '[:lower:]')"

  if [ -n "${PUBLIC_HOST:-}" ]; then
    if valid_domain "${PUBLIC_HOST}"; then
      host_override="${PUBLIC_HOST}"
    else
      echo "Error: PUBLIC_HOST is not a valid domain name: ${PUBLIC_HOST}"
      exit 1
    fi
  fi

  if [ -n "${PUBLIC_IP:-}" ]; then
    if valid_public_ipv4 "${PUBLIC_IP}"; then
      PUBLIC_IP_FAMILY=4
    elif valid_public_ipv6 "${PUBLIC_IP}"; then
      PUBLIC_IP_FAMILY=6
    else
      echo "Error: PUBLIC_IP is not a valid public IPv4 or IPv6 address: ${PUBLIC_IP}"
      echo "For a domain name, use PUBLIC_HOST instead."
      exit 1
    fi
  else
    case "${ver}" in
      4|ipv4|v4)
        PUBLIC_IP="$(detect_public_ipv4 || true)"
        PUBLIC_IP_FAMILY=4
        ;;
      6|ipv6|v6)
        PUBLIC_IP="$(detect_public_ipv6 || true)"
        PUBLIC_IP_FAMILY=6
        ;;
      *)
        if PUBLIC_IP="$(detect_public_ipv4)"; then
          PUBLIC_IP_FAMILY=4
        elif PUBLIC_IP="$(detect_public_ipv6)"; then
          PUBLIC_IP_FAMILY=6
        else
          PUBLIC_IP=""
        fi
        ;;
    esac
  fi

  if [ -z "${PUBLIC_IP}" ]; then
    if [ -n "${host_override}" ]; then
      # No detectable IP, but a client-facing domain was given: choose the
      # listen family from PUBLIC_IP_VERSION (default IPv4).
      case "${ver}" in 6|ipv6|v6) PUBLIC_IP_FAMILY=6 ;; *) PUBLIC_IP_FAMILY=4 ;; esac
    else
      echo "Failed to detect a public IP address."
      echo "Set PUBLIC_IP=<addr> (IPv4/IPv6), PUBLIC_HOST=<domain>, or PUBLIC_IP_VERSION=4|6|auto."
      exit 1
    fi
  fi

  # Client-facing hosts. A PUBLIC_HOST domain overrides the IP literal.
  if [ -n "${host_override}" ]; then
    PUBLIC_CLASH_HOST="${host_override}"
    PUBLIC_URI_HOST="${host_override}"
    PUBLIC_URL_HOST="${host_override}"
  else
    PUBLIC_CLASH_HOST="${PUBLIC_IP}"
    PUBLIC_URI_HOST="$(format_host_for_uri "${PUBLIC_IP}")"
    PUBLIC_URL_HOST="${PUBLIC_URI_HOST}"
  fi

  # When the user did not pin LISTEN_ADDRESS, bind :: on an IPv6 node.
  if [ -z "${LISTEN_ADDRESS_WAS_SET:-}" ] && [ "${PUBLIC_IP_FAMILY}" = 6 ]; then
    LISTEN_ADDRESS="::"
  fi

  echo "Public IP: ${PUBLIC_IP:-<not detected>} (IPv${PUBLIC_IP_FAMILY})"
  [ -n "${host_override}" ] && echo "Client-facing host: ${host_override}"

  resolve_dns_profile
}

write_dns_config() {
  local profile="${DNS_EFFECTIVE_PROFILE:-mixed}"
  local dns_file="${RAYLINK_TEMPLATES}/clash/dns/${profile}.yaml"

  if [ ! -f "${dns_file}" ]; then
    dns_file="${RAYLINK_TEMPLATES}/clash/dns/foreign.yaml"
  fi

  cat "${dns_file}"
}
