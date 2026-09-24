<?php
/**
 * Plugin Name: SMTP from environment
 * Description: Sends WordPress mail through the SMTP server set in the SMTP_* environment variables. Does nothing when SMTP_HOST is empty.
 */

defined('ABSPATH') || exit;

if (!getenv('SMTP_HOST')) {
    return;
}

add_action('phpmailer_init', static function ($mailer): void {
    $mailer->isSMTP();
    $mailer->Host = getenv('SMTP_HOST');
    $mailer->Port = (int) (getenv('SMTP_PORT') ?: 587);

    // SMTP_SECURE: "tls" (STARTTLS), "ssl" (implicit TLS), "none", or empty
    // (use STARTTLS if the server offers it).
    $secure = strtolower((string) getenv('SMTP_SECURE'));
    $mailer->SMTPSecure = in_array($secure, ['tls', 'ssl'], true) ? $secure : '';
    $mailer->SMTPAutoTLS = $secure !== 'none';

    $user = getenv('SMTP_USER');
    if ($user) {
        $mailer->SMTPAuth = true;
        $mailer->Username = $user;
        $mailer->Password = (string) getenv('SMTP_PASSWORD');
    }
});

add_filter('wp_mail_from', static fn (string $from): string => getenv('SMTP_FROM') ?: $from);
add_filter('wp_mail_from_name', static fn (string $name): string => getenv('SMTP_FROM_NAME') ?: $name);
