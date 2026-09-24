#!/bin/sh
# Installs WordPress + Easy Digital Downloads and applies the initial store settings.
#
# Runs on every `docker compose up` and is safe to repeat:
# - WordPress and Easy Digital Downloads are installed only if missing.
# - Initial settings (language, country, currency, permalinks...) are applied
#   only once, so changes made later in the admin are kept.
# - EDD_VERSION, when set, pins Easy Digital Downloads to that exact version on every run;
#   when empty, the latest version is installed once and then updated from the
#   admin as usual.
# - The store emails' sender follows SMTP_FROM / SMTP_FROM_NAME when set.
# - The Redis object cache is enabled or disabled to match REDIS_HOST.
set -eu

cd /var/www/html

INIT_OPTION="docker_stack_initialized"

# Redis turned off: remove the Redis Object Cache drop-in before loading
# WordPress, so nothing tries to reach a Redis server that isn't there.
if [ -z "${REDIS_HOST}" ] && grep -qs 'Redis Object Cache' wp-content/object-cache.php; then
    echo "==> REDIS_HOST is empty: removing the Redis object cache drop-in"
    rm -f wp-content/object-cache.php
    redis_disabled=1
fi

if ! wp core is-installed 2>/dev/null; then
    echo "==> Installing WordPress at ${WP_URL}"
    wp core install \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email
fi

current_edd="$(wp plugin get easy-digital-downloads --field=version 2>/dev/null || true)"
if [ -z "${current_edd}" ]; then
    echo "==> Installing Easy Digital Downloads ${EDD_VERSION:-(latest)}"
    wp plugin install easy-digital-downloads ${EDD_VERSION:+--version="${EDD_VERSION}"}
elif [ -n "${EDD_VERSION}" ] && [ "${current_edd}" != "${EDD_VERSION}" ]; then
    echo "==> Pinning Easy Digital Downloads to ${EDD_VERSION} (was ${current_edd})"
    wp plugin install easy-digital-downloads --version="${EDD_VERSION}" --force
fi

if ! wp option get "${INIT_OPTION}" >/dev/null 2>&1; then
    echo "==> Initial settings"
    # Activation creates the store pages (checkout, confirmation, receipt...).
    wp plugin activate easy-digital-downloads
    # Sample plugins bundled with WordPress.
    wp plugin delete akismet hello 2>/dev/null || true
    if [ "${WP_LOCALE}" != "en_US" ]; then
        wp language core install "${WP_LOCALE}" --activate
        wp language plugin install easy-digital-downloads "${WP_LOCALE}" || true
    fi
    # Store country and currency (CLP: added by mu-plugins/currencies.php).
    wp eval '
        edd_update_option("base_country", getenv("EDD_COUNTRY"));
        edd_update_option("currency", getenv("EDD_CURRENCY"));
        edd_update_option("currency_position", "before");
        edd_update_option("thousands_separator", ".");
        edd_update_option("decimal_separator", ",");
    '
    # Skip the onboarding wizard.
    wp option update edd_onboarding_completed 1
    wp transient delete edd_onboarding_redirect > /dev/null || true
    # Pretty permalinks (Caddy routes them to index.php, see config/caddy).
    wp rewrite structure '/%postname%/'
    wp rewrite flush
    wp option add "${INIT_OPTION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

# Store emails' sender follows SMTP_FROM / SMTP_FROM_NAME when set (Easy
# Digital Downloads has its own sender settings, which win over WordPress').
if [ -n "${SMTP_FROM}" ]; then
    # shellcheck disable=SC2016 # PHP code: $ is not shell expansion
    wp eval '
        foreach (["from_email" => getenv("SMTP_FROM"), "from_name" => getenv("SMTP_FROM_NAME")] as $key => $value) {
            if ($value !== "" && $value !== false && edd_get_option($key) !== $value) {
                edd_update_option($key, $value);
                echo "    ", $key, " updated\n";
            }
        }
    '
fi

if [ -n "${REDIS_HOST}" ]; then
    if ! wp plugin is-active redis-cache 2>/dev/null; then
        echo "==> Enabling Redis object cache (${REDIS_HOST})"
        wp plugin install redis-cache --activate
    fi
    wp redis status | grep -q '^Drop-in: Valid' || wp redis enable --force
elif [ -n "${redis_disabled:-}" ]; then
    wp plugin deactivate redis-cache
fi

echo "==> Done: WordPress $(wp core version), Easy Digital Downloads $(wp plugin get easy-digital-downloads --field=version)"
echo "    Store: ${WP_URL}"
echo "    Admin: ${WP_URL}/wp-admin (user: ${WP_ADMIN_USER})"
