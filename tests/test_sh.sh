#!/usr/bin/env bash
# Тесты toolsai_check.sh на заглушках: значения подставляются переменными окружения.
cd "$(dirname "$0")/.." || exit 1
fail=0
run() { # name expected-substring env...
  local name=$1 want=$2; shift 2
  local out; out=$(env "$@" bash toolsai_check.sh 2>&1)
  if grep -qF -- "$want" <<<"$out"; then echo "ok   $name"; else echo "FAIL $name: нет «$want»"; echo "$out"; fail=1; fi
}
base="TOOLSAI_CHECK_DOCKER=1 TOOLSAI_CHECK_VIRT=kvm TOOLSAI_CHECK_PORTS=80"
run "мало ресурсов"   "Итог: не хватает:" $base TOOLSAI_CHECK_CORES=4 TOOLSAI_CHECK_MEM_GB=8 TOOLSAI_CHECK_DISK_GB=10 TOOLSAI_CHECK_AVX2=1
run "уровень none"    "level=none;ok=0" $base TOOLSAI_CHECK_CORES=4 TOOLSAI_CHECK_MEM_GB=8 TOOLSAI_CHECK_DISK_GB=10 TOOLSAI_CHECK_AVX2=1
run "минимум"         "level=min;ok=1" $base TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "средний"         "level=mid;ok=1" $base TOOLSAI_CHECK_CORES=12 TOOLSAI_CHECK_MEM_GB=24 TOOLSAI_CHECK_DISK_GB=30 TOOLSAI_CHECK_AVX2=1
run "с запасом"       "level=full;ok=1" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=32 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=1
run "память режет"    "level=min;ok=1" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=1
run "нет AVX2"        "AVX2 нет" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=32 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=0
run "нет AVX2 итог"   "level=none;ok=0" $base TOOLSAI_CHECK_CORES=16 TOOLSAI_CHECK_MEM_GB=32 TOOLSAI_CHECK_DISK_GB=50 TOOLSAI_CHECK_AVX2=0
run "lxc"             "nesting=1" TOOLSAI_CHECK_DOCKER=1 TOOLSAI_CHECK_VIRT=lxc TOOLSAI_CHECK_PORTS= TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
run "без docker"      "Docker: не найден" TOOLSAI_CHECK_DOCKER=0 TOOLSAI_CHECK_VIRT=kvm TOOLSAI_CHECK_PORTS= TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1
# код не содержит имён хоста/адресов
out=$(env $base TOOLSAI_CHECK_CORES=8 TOOLSAI_CHECK_MEM_GB=16 TOOLSAI_CHECK_DISK_GB=20 TOOLSAI_CHECK_AVX2=1 bash toolsai_check.sh | tail -1)
case $out in TAI1\;*) echo "ok   строка-код";; *) echo "FAIL строка-код: $out"; fail=1;; esac
exit $fail
