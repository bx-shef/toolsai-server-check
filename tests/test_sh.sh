#!/usr/bin/env bash
# Тесты toolsai_check.sh на заглушках: значения подставляются переменными окружения.
cd "$(dirname "$0")/.." || exit 1
fail=0
ARGS=""
run() { # name expected-substring env...
  local name=$1 want=$2; shift 2
  local out; out=$(env "$@" bash toolsai_check.sh $ARGS 2>&1)
  if grep -qF -- "$want" <<<"$out"; then echo "ok   $name"; else echo "FAIL $name: нет «$want»"; echo "$out"; fail=1; fi
}
base="TOOLSAI_CHECK_DOCKER=1 TOOLSAI_CHECK_VIRT=kvm TOOLSAI_CHECK_PORTS=80"
run "мало ресурсов"   "Итог: не готов" $base TOOLSAI_CHECK_CORES=4 TOOLSAI_CHECK_MEM_GB=8 TOOLSAI_CHECK_DISK_GB=10 TOOLSAI_CHECK_AVX2=1
run "уровень none"    "Уровень по ресурсам: ниже минимума" $base TOOLSAI_CHECK_CORES=4 TOOLSAI_CHECK_MEM_GB=8 TOOLSAI_CHECK_DISK_GB=10 TOOLSAI_CHECK_AVX2=1
run "минимум"         "Уровень по ресурсам: минимум" $base TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "средний"         "Уровень по ресурсам: средний" $base TOOLSAI_CHECK_CORES=12 TOOLSAI_CHECK_MEM_GB=24 TOOLSAI_CHECK_DISK_GB=30 TOOLSAI_CHECK_AVX2=1
run "с запасом"       "Уровень по ресурсам: с запасом" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=32 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=1
run "память режет"    "Уровень по ресурсам: минимум" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=1
run "нет AVX2"        "нет — модели не запустятся" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=32 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=0
run "нет AVX2 итог"   "Уровень по ресурсам: ниже минимума" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=32 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=0
run "lxc"             "nesting=1" TOOLSAI_CHECK_DOCKER=1 TOOLSAI_CHECK_VIRT=lxc TOOLSAI_CHECK_PORTS= TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "без docker"      "Docker: не найден" TOOLSAI_CHECK_DOCKER=0 TOOLSAI_CHECK_VIRT=kvm TOOLSAI_CHECK_PORTS= TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
# режим --services-only (отдельная ВМ под сервисы)
ARGS="--services-only"
run "svc: 6/10/20 минимум" "Ядра процессора: 6 (норма 6 / 10)" $base TOOLSAI_CHECK_CORES=6 TOOLSAI_CHECK_MEM_GB=10 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "svc: 10/13/30 средний" "Уровень по ресурсам: средний" $base TOOLSAI_CHECK_CORES=10 TOOLSAI_CHECK_MEM_GB=13 TOOLSAI_CHECK_DISK_GB=30 TOOLSAI_CHECK_AVX2=1
run "svc: уровня запаса нет" "Уровень по ресурсам: средний" $base TOOLSAI_CHECK_CORES=32 TOOLSAI_CHECK_MEM_GB=64 TOOLSAI_CHECK_DISK_GB=500 TOOLSAI_CHECK_AVX2=1
run "svc: 5 ядер мало" "Итог: не готов" $base TOOLSAI_CHECK_CORES=5 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=1
run "svc: 8/16 хватает (в режиме all — минимум)" "Итог: готово" $base TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=11 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "svc: заголовок" "только под сервисы" $base TOOLSAI_CHECK_CORES=6 TOOLSAI_CHECK_MEM_GB=10 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
ARGS=""
# код не содержит имён хоста/адресов
out=$(env $base TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1 bash toolsai_check.sh)
if grep -qE "TAI1|Пришлите|пришлите" <<<"$out"; then echo "FAIL просьба прислать результат"; fail=1; else echo "ok   нечего присылать"; fi
run "подсказка при нехватке" "→ добавьте ядра" TOOLSAI_CHECK_DOCKER=1 TOOLSAI_CHECK_VIRT=kvm TOOLSAI_CHECK_PORTS= TOOLSAI_CHECK_CORES=4 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "сводка: что исправить" "✗ ядра: есть 4, нужно от 8" TOOLSAI_CHECK_DOCKER=1 TOOLSAI_CHECK_VIRT=kvm TOOLSAI_CHECK_PORTS= TOOLSAI_CHECK_CORES=4 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
# версия в скриптах = последняя в CHANGELOG
cl=$(grep -m1 '^## ' CHANGELOG.md | sed 's/^## //' | tr -d '\r')
shv=$(sed -n 's/^VERSION="\(.*\)"/\1/p' toolsai_check.sh)
phpv=$(sed -n "s/.*TOOLSAI_CHECK_VERSION = '\(.*\)';.*/\1/p" toolsai_check.php | tr -d '\r')
if [ "$cl" = "$shv" ] && [ "$cl" = "$phpv" ]; then echo "ok   версия $cl"; else echo "FAIL версия: changelog=$cl sh=$shv php=$phpv"; fail=1; fi
exit $fail
