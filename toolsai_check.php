<?php
/**
 * Tools AI — проверка портала Битрикс24.
 *
 * Положить в корень портала (/home/bitrix/www/), открыть https://ваш-портал/toolsai_check.php
 * под администратором. Файл только читает: ничего не меняет и не отправляет данных.
 * Единственное изменение — кнопка «Удалить файл» удаляет сам скрипт.
 *
 * Необязательный параметр ?model=https://адрес-модели — проверить исходящий HTTPS до модели.
 * Параметр ?layout=split — Битрикс24 на отдельной ВМ, сервисы на другой: порог диска не применяется
 * (сервисы проверяются на своей ВМ: sudo bash toolsai_check.sh --services-only).
 */

const TOOLSAI_CHECK_VERSION = '1.1.4';
const TOOLSAI_LICENSE_HOST = 'license.bx-shef.by';
const TOOLSAI_MIN_DISK_GB = 20; // «минимум» из системных требований, свободно сверх Битрикса

/** Минимальные версии модулей Битрикс24: модуль => версия (null — достаточно наличия). */
function toolsai_min_modules(): array
{
    return ['ai' => '26.1000', 'crm' => '26.800', 'im' => null];
}

/** Нужные расширения PHP. */
function toolsai_required_extensions(): array
{
    return ['curl', 'json', 'mbstring', 'openssl', 'zlib'];
}

/** Строка результата: [статус ok|warn|fail|info, что проверено, найдено, норма, что сделать если не так]. */
function toolsai_row(string $status, string $title, string $detail = '', string $norm = '', string $hint = ''): array
{
    return [$status, $title, $detail, $norm, $hint];
}

function toolsai_check_php(string $version, array $loaded): array
{
    $rows = [toolsai_row('info', 'Версия PHP', $version, 'справочно')];
    foreach (toolsai_required_extensions() as $ext) {
        $rows[] = in_array($ext, $loaded, true)
            ? toolsai_row('ok', "Расширение $ext", 'есть', 'должно быть включено')
            : toolsai_row('fail', "Расширение $ext", 'нет', 'должно быть включено', 'включите расширение $ext в настройках PHP и перезапустите веб-сервер');
    }
    return $rows;
}

/** @param array<string,string|null> $installed модуль => версия (null — модуля нет) */
function toolsai_check_modules(array $installed): array
{
    $rows = [];
    foreach (toolsai_min_modules() as $module => $min) {
        $ver = $installed[$module] ?? null;
        if ($ver === null) {
            $rows[] = toolsai_row('fail', "Модуль $module", 'не установлен', $min ? "версия не ниже $min" : 'должен быть установлен', 'установите модуль в разделе «Настройки → Настройки продукта → Модули»');
        } elseif ($min !== null && version_compare($ver, $min, '<')) {
            $rows[] = toolsai_row('fail', "Модуль $module", "версия $ver", "версия не ниже $min", 'обновите Битрикс24 в разделе «Настройки → Обновления»');
        } else {
            $rows[] = toolsai_row('ok', "Модуль $module", 'версия ' . $ver, $min ? "версия не ниже $min" : 'должен быть установлен');
        }
    }
    return $rows;
}

function toolsai_check_cron(bool $agentsOnCron, bool $cronDefined): array
{
    return ($agentsOnCron && $cronDefined)
        ? [toolsai_row('ok', 'Агенты на cron', 'включено', 'включено')]
        : [toolsai_row('warn', 'Агенты на cron', 'не включено', 'включено', 'переведите агентов на cron: фоновые задачи модулей иначе идут только по обращениям к страницам')];
}

function toolsai_check_disk(float $freeGb, bool $split = false): array
{
    $text = round($freeGb, 1) . ' ГБ свободно';
    if ($split) { // Битрикс24 на отдельной ВМ: сервисы стоят на другой, порог не применяется
        return [toolsai_row('info', 'Диск', $text, 'справочно: сервисы на другой ВМ')];
    }
    return $freeGb >= TOOLSAI_MIN_DISK_GB
        ? [toolsai_row('ok', 'Диск', $text, 'от +' . TOOLSAI_MIN_DISK_GB . ' ГБ сверх Битрикса')]
        : [toolsai_row('fail', 'Диск', $text, 'от +' . TOOLSAI_MIN_DISK_GB . ' ГБ сверх Битрикса', 'освободите место или расширьте диск')];
}

function toolsai_check_memory(string $limit): array
{
    return [toolsai_row('info', 'Память PHP (memory_limit)', $limit === '-1' ? 'без ограничения' : $limit, 'справочно')];
}

/** @param array<string,bool|null> $reach хост => доступен (null — не проверялся) */
function toolsai_check_network(array $reach): array
{
    $rows = [];
    foreach ($reach as $host => $ok) {
        if ($ok === null) {
            $rows[] = toolsai_row('info', "HTTPS до $host", 'не проверялся', 'добавьте ?model=https://адрес-модели, если нужна своя модель');
        } else {
            $rows[] = $ok
                ? toolsai_row('ok', "HTTPS до $host", 'доступен', 'исходящий доступ открыт')
                : toolsai_row('fail', "HTTPS до $host", 'нет соединения', 'исходящий доступ открыт', 'откройте исходящий HTTPS (порт 443) до этого адреса в файрволе и прокси');
        }
    }
    return $rows;
}

/** Итог: ['done' => bool, 'missing' => string[]]. */
function toolsai_summary(array $rows): array
{
    $missing = [];
    foreach ($rows as [$status, $title, $detail, $norm, $hint]) {
        if ($status === 'fail') {
            $missing[] = $title . ($detail !== '' ? ': ' . $detail : '') . ($norm !== '' ? ' (норма: ' . $norm . ')' : '') . ($hint !== '' ? ' → ' . $hint : '');
        }
    }
    return ['done' => $missing === [], 'missing' => $missing];
}

/** Только https и допустимое имя хоста. */
function toolsai_host_from_url(string $url): ?string
{
    $p = parse_url($url);
    if (!$p || ($p['scheme'] ?? '') !== 'https' || empty($p['host'])) {
        return null;
    }
    return preg_match('/^[a-z0-9.-]+$/i', $p['host']) ? $p['host'] : null;
}

/** Проверочный HTTPS-запрос без данных (HEAD). Любой HTTP-ответ — соединение есть. */
function toolsai_probe_https(string $host): bool
{
    if (!function_exists('curl_init')) {
        return false;
    }
    $ch = curl_init("https://$host/");
    curl_setopt_array($ch, [CURLOPT_NOBODY => true, CURLOPT_TIMEOUT => 8, CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_RETURNTRANSFER => true]);
    curl_exec($ch);
    $ok = curl_errno($ch) === 0;
    curl_close($ch);
    return $ok;
}

function toolsai_render(array $sections, array $summary, bool $canDelete): string
{
    $icon = ['ok' => '✅', 'warn' => '⚠️', 'fail' => '❌', 'info' => 'ℹ️'];
    $h = static fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
    $out = '<!doctype html><meta charset="utf-8"><title>Tools AI — проверка сервера</title>'
        . '<style>body{font:15px sans-serif;margin:2em auto;max-width:760px}table{border-collapse:collapse;width:100%}'
        . 'td{border-bottom:1px solid #ddd;padding:6px}h2{margin-top:1.4em}.done{color:#1a7f37}.miss{color:#c62828}</style>'
        . '<h1>Tools AI — проверка сервера</h1><p>Файл только читает: ничего не меняет и не отправляет. Версия ' . TOOLSAI_CHECK_VERSION . '.</p>'
        . '<p>✅ в порядке, ⚠️ стоит проверить, ❌ нужно исправить, ℹ️ справочно.</p>';
    foreach ($sections as $title => $rows) {
        $out .= '<h2>' . $h((string)$title) . '</h2><table><tr><th></th><th>Проверено</th><th>Найдено</th><th>Норма</th></tr>';
        foreach ($rows as $row) {
            [$st, $name, $detail] = $row;
            $norm = $row[3] ?? '';
            $hint = $row[4] ?? '';
            $out .= '<tr><td width="40">' . $icon[$st] . '</td><td>' . $h($name) . '</td><td>' . $h($detail) . '</td><td>' . $h($norm) . '</td></tr>';
            if ($hint !== '' && $st !== 'ok' && $st !== 'info') {
                $out .= '<tr><td></td><td colspan="3">→ ' . $h($hint) . '</td></tr>';
            }
        }
        $out .= '</table>';
    }
    if ($summary['done']) {
        $out .= '<h2 class="done">Итог: готово — портал подходит для Tools AI.</h2>';
    } else {
        $out .= '<h2 class="miss">Итог: не готов к Tools AI. Исправьте:</h2><ul>';
        foreach ($summary['missing'] as $m) {
            $out .= '<li>' . $h($m) . '</li>';
        }
        $out .= '</ul>';
    }
    $out .= '<p>Для своих сервисов (распознавание, лёгкая модель, файлы) запустите на сервере проверку <code>toolsai_check.sh</code> (см. README).</p>';
    if ($canDelete) {
        $out .= '<form method="post"><input type="hidden" name="sessid" value="' . $h(bitrix_sessid()) . '">'
            . '<button name="delete_self" value="1">Удалить файл</button></form>';
    }
    return $out;
}

/** Сбор данных портала. Выполняется только при открытии файла в браузере. */
function toolsai_run(): void
{
    $_SERVER['DOCUMENT_ROOT'] = $_SERVER['DOCUMENT_ROOT'] ?? __DIR__;
    define('NO_KEEP_STATISTIC', true);
    require $_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php';
    global $USER;
    header('Content-Type: text/html; charset=utf-8');
    if (!is_object($USER) || !$USER->IsAdmin()) {
        http_response_code(403);
        exit('Доступ только для администратора портала. Войдите под администратором и откройте страницу снова.');
    }
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['delete_self'])) {
        if (!check_bitrix_sessid()) {
            http_response_code(400);
            exit('Сессия устарела. Обновите страницу.');
        }
        $ok = @unlink(__FILE__);
        exit($ok ? 'Файл удалён.' : 'Не удалось удалить файл — удалите toolsai_check.php вручную.');
    }

    $installed = [];
    foreach (array_keys(toolsai_min_modules()) as $m) {
        $installed[$m] = \Bitrix\Main\ModuleManager::isModuleInstalled($m)
            ? (string)(\Bitrix\Main\ModuleManager::getVersion($m) ?: '0') : null;
    }
    $reach = [TOOLSAI_LICENSE_HOST => toolsai_probe_https(TOOLSAI_LICENSE_HOST)];
    $modelHost = toolsai_host_from_url((string)($_GET['model'] ?? ''));
    $reach[$modelHost ?? 'адрес модели'] = $modelHost !== null ? toolsai_probe_https($modelHost) : null;

    $sections = [
        'PHP' => toolsai_check_php(PHP_VERSION, get_loaded_extensions()),
        'Битрикс24' => array_merge(
            [toolsai_row('info', 'Версия продукта', defined('SM_VERSION') ? SM_VERSION : 'неизвестно')],
            toolsai_check_modules($installed),
            toolsai_check_cron(
                \Bitrix\Main\Config\Option::get('main', 'agents_use_crontab', 'N') === 'Y',
                defined('BX_CRONTAB_SUPPORT') && BX_CRONTAB_SUPPORT === true
            )
        ),
        'Сеть' => toolsai_check_network($reach),
        'Сервер' => array_merge(
            toolsai_check_disk((float)disk_free_space($_SERVER['DOCUMENT_ROOT']) / 1073741824, ($_GET['layout'] ?? '') === 'split'),
            toolsai_check_memory((string)ini_get('memory_limit'))
        ),
    ];
    $all = array_merge(...array_values($sections));
    echo toolsai_render($sections, toolsai_summary($all), is_writable(__FILE__));
}

if (!defined('TOOLSAI_CHECK_TEST')) {
    toolsai_run();
}
