<?php
/**
 * Extra wp-config.php settings, loaded through WORDPRESS_CONFIG_EXTRA.
 *
 * Every value comes from an environment variable set in compose.yaml, so the
 * same code works for development and production.
 */

$env_bool = static function (string $name, bool $default): bool {
    $value = getenv($name);
    return $value === false || $value === ''
        ? $default
        : filter_var($value, FILTER_VALIDATE_BOOLEAN);
};

// Site URL comes from the environment, never from the database.
define('WP_HOME', getenv('WP_URL'));
define('WP_SITEURL', getenv('WP_URL'));
define('WP_ENVIRONMENT_TYPE', getenv('WP_ENVIRONMENT_TYPE') ?: 'production');

// Same limit as PHP.
define('WP_MEMORY_LIMIT', getenv('PHP_MEMORY_LIMIT') ?: '256M');
define('WP_MAX_MEMORY_LIMIT', getenv('PHP_MEMORY_LIMIT') ?: '256M');

// WP-Cron is triggered by the `cron` service, not by page visits.
define('DISABLE_WP_CRON', true);

// No theme/plugin file editor in the admin.
define('DISALLOW_FILE_EDIT', $env_bool('WP_DISALLOW_FILE_EDIT', true));

// Must-use plugins shipped with the stack (read-only mount, see config/wordpress/mu-plugins).
define('WPMU_PLUGIN_DIR', '/usr/local/share/wordpress/mu-plugins');

// Redis object cache (Redis Object Cache plugin), only when REDIS_HOST is set.
if (getenv('REDIS_HOST')) {
    define('WP_REDIS_HOST', getenv('REDIS_HOST'));
    define('WP_REDIS_PORT', (int) (getenv('REDIS_PORT') ?: 6379));
    define('WP_REDIS_CLIENT', 'predis');
    define('WP_REDIS_PREFIX', getenv('REDIS_PREFIX') ?: 'wp');
} else {
    // Keeps the site working if the plugin's drop-in is still there.
    define('WP_REDIS_DISABLED', true);
}

unset($env_bool);
