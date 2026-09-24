#!/bin/sh
# Runs due WP-Cron events (including Easy Digital Downloads' Action Scheduler) every
# CRON_INTERVAL seconds. WP-Cron on page visits is disabled in wp-config.
set -u

HEARTBEAT=/tmp/cron-heartbeat

case "${1:-run}" in
    health)
        # Healthy if the loop completed a pass within 3 intervals.
        [ -n "$(find "${HEARTBEAT}" -mmin -"$(( (CRON_INTERVAL * 3 + 59) / 60 ))" 2>/dev/null)" ]
        exit
        ;;
esac

cd /var/www/html || exit 1
echo "==> Running WP-Cron every ${CRON_INTERVAL}s"
while :; do
    if wp core is-installed 2>/dev/null; then
        wp cron event run --due-now --quiet || echo "WP-Cron run failed" >&2
    fi
    touch "${HEARTBEAT}"
    sleep "${CRON_INTERVAL}"
done
