<?php
/**
 * Plugin Name: Store currencies
 * Description: Adds the Chilean peso (CLP: "$", no decimals) to Easy Digital Downloads' currencies.
 */

defined('ABSPATH') || exit;

add_filter('edd_currencies', static function (array $currencies): array {
    $currencies['CLP'] = __('Chilean Peso (&#36;)', 'easy-digital-downloads');
    return $currencies;
});

add_filter('edd_currency_decimal_count', static function (int $decimals, $currency = ''): int {
    $currency = $currency ?: (function_exists('edd_get_currency') ? edd_get_currency() : '');
    return $currency === 'CLP' ? 0 : $decimals;
}, 10, 2);

add_filter('edd_currency_symbol', static function (string $symbol, $code = ''): string {
    return $code === 'CLP' ? '&#36;' : $symbol;
}, 10, 2);

// Chilean format: "$12.345" (no space between symbol and amount).
add_filter('edd_currency_prefix', static function (string $prefix, $code = ''): string {
    return $code === 'CLP' ? '&#36;' : $prefix;
}, 10, 2);
