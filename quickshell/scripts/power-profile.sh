#!/usr/bin/env bash
# Power profile via TLP.
#
# The usual `powerprofilesctl` needs power-profiles-daemon, which CONFLICTS with
# TLP — installing it would uninstall TLP. So the profile is driven by TLP
# instead, which exposes exactly three modes matching the UI's three stops:
#
#     tlp performance | balanced | power-saver
#
# Reading uses the kernel's /sys/firmware/acpi/platform_profile rather than
# asking TLP. That file is what TLP actually applied, so the UI reflects the
# real state — including changes TLP makes on its own when you plug in or
# unplug. It's also world-readable, so reading needs no privileges at all.
#
#   tlp performance  -> platform_profile = performance
#   tlp balanced     -> platform_profile = balanced
#   tlp power-saver  -> platform_profile = low-power
#
# Setting needs root; /etc/sudoers.d/tlp-profile grants NOPASSWD for exactly
# those three fixed commands and nothing else.
set -u
PP=/sys/firmware/acpi/platform_profile

kernel_to_key() {
    case "${1:-}" in
        performance) echo performance ;;
        balanced)    echo balanced ;;
        low-power)   echo power-saver ;;
        *)           echo balanced ;;   # unknown/unsupported hardware
    esac
}

case "${1:-get}" in
    get)
        [ -r "$PP" ] || { echo balanced; exit 0; }
        kernel_to_key "$(cat "$PP" 2>/dev/null)"
        ;;
    set)
        case "${2:-}" in
            performance|balanced|power-saver)
                # -n: never prompt. If the sudoers rule is missing we fail
                # silently rather than hanging the shell on a password prompt.
                sudo -n /usr/sbin/tlp "$2" >/dev/null 2>&1
                ;;
        esac
        ;;
    *)
        echo "usage: ${0##*/} get | set {performance|balanced|power-saver}" >&2
        exit 2
        ;;
esac
exit 0
