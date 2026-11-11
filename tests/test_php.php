<?php
// Тесты toolsai_check.php на заглушках: php tests/test_php.php
define('TOOLSAI_CHECK_TEST', true);
require __DIR__ . '/../toolsai_check.php';
function bitrix_sessid(): string { return 'stub'; }

$fail = 0;
function t(string $name, bool $cond): void { global $fail; echo ($cond ? 'ok   ' : 'FAIL ') . $name . "\n"; if (!$cond) $fail = 1; }
function statuses(array $rows): array { return array_column($rows, 0); }

// расширения
t('все расширения есть', !in_array('fail', statuses(toolsai_check_php('8.3.0', toolsai_required_extensions())), true));
t('нет curl', in_array('fail', statuses(toolsai_check_php('8.3.0', ['json', 'mbstring', 'openssl', 'zlib'])), true));

// модули
$ok = toolsai_check_modules(['ai' => '26.1000.0', 'crm' => '26.800.0', 'im' => '25.0.0']);
t('модули в норме', statuses($ok) === ['ok', 'ok', 'ok']);
$old = toolsai_check_modules(['ai' => '25.100.0', 'crm' => '26.800.0', 'im' => '25.0.0']);
t('старый ai', $old[0][0] === 'fail');
t('нет im', toolsai_check_modules(['ai' => '26.1000.0', 'crm' => '26.900.0', 'im' => null])[2][0] === 'fail');
t('crm 26.1000 новее 26.800', toolsai_check_modules(['ai' => '26.1000.0', 'crm' => '26.1000.0', 'im' => '1'])[1][0] === 'ok');

// cron, диск, память, сеть
t('cron выключен', toolsai_check_cron(false, false)[0][0] === 'warn');
t('cron включён', toolsai_check_cron(true, true)[0][0] === 'ok');
t('диск мало', toolsai_check_disk(5.0)[0][0] === 'fail');
t('диск split: справочно', toolsai_check_disk(5.0, true)[0][0] === 'info');
t('диск норма', toolsai_check_disk(20.0)[0][0] === 'ok');
t('память без лимита', toolsai_check_memory('-1')[0][2] === 'без ограничения');
$net = toolsai_check_network(['a.example' => true, 'b.example' => false, 'c' => null]);
t('сеть', statuses($net) === ['ok', 'fail', 'info']);

// итог
t('итог: готово', toolsai_summary($ok)['done'] === true);
$s = toolsai_summary($old);
t('итог: не хватает', $s['done'] === false && count($s['missing']) === 1);

// адрес модели
t('https принят', toolsai_host_from_url('https://api.example.com/v1') === 'api.example.com');
t('http отклонён', toolsai_host_from_url('http://api.example.com') === null);
t('мусор отклонён', toolsai_host_from_url('file:///etc/passwd') === null);

// вывод: экранирование и кнопка
$html = toolsai_render(['T<' => [['ok', '<b>', 'x']]], ['done' => true, 'missing' => []], true);
t('экранирование', !str_contains($html, '<b>') && str_contains($html, '&lt;b&gt;'));
t('кнопка удаления с сессией', str_contains($html, 'delete_self') && str_contains($html, 'name="sessid"'));
t('итог в выводе', str_contains($html, 'Итог: готово'));
t('без кнопки', !str_contains(toolsai_render([], ['done' => true, 'missing' => []], false), 'delete_self'));
$bad = toolsai_render([], ['done' => false, 'missing' => ['диск']], false);
t('не хватает в выводе', str_contains($bad, 'Итог: не готов к Tools AI. Исправьте:') && str_contains($bad, 'диск'));
exit($fail);
