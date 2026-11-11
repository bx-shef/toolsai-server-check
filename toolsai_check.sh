#!/usr/bin/env bash
# Tools AI — проверка сервера для своих сервисов. Только читает, ничего не меняет и не отправляет.
# Запуск: sudo bash toolsai_check.sh
# Пороги — из системных требований Tools AI (три уровня: минимум / средний / с запасом).

VERSION="1.1.2"

# Уровни: ядра / память ГБ / диск ГБ свободно сверх Битрикса
MIN_CORES=8;  MIN_MEM=16; MIN_DISK=20
MID_CORES=12; MID_MEM=24; MID_DISK=30
FUL_CORES=16; FUL_MEM=32; FUL_DISK=50

# Режим --services-only: отдельная ВМ только под сервисы (Битрикс24 на другой ВМ).
# Уровни — расчёт по таблице требований; уровня «с запасом» нет.
SVC_MIN_CORES=6;  SVC_MIN_MEM=10; SVC_MIN_DISK=20
SVC_MID_CORES=10; SVC_MID_MEM=13; SVC_MID_DISK=30
MODE=all

# Переопределения нужны тестам (подставляют значения вместо чтения системы).
detect_cores() { [ -n "${TOOLSAI_CHECK_CORES:-}" ] && { echo "$TOOLSAI_CHECK_CORES"; return; }; nproc 2>/dev/null || echo 0; }
detect_mem_gb() {
  [ -n "${TOOLSAI_CHECK_MEM_GB:-}" ] && { echo "$TOOLSAI_CHECK_MEM_GB"; return; }
  local kb; kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null); kb=${kb:-0}
  echo $(( (kb + 524288) / 1048576 ))   # округление до ближайшего ГБ
}
detect_disk_gb() {
  [ -n "${TOOLSAI_CHECK_DISK_GB:-}" ] && { echo "$TOOLSAI_CHECK_DISK_GB"; return; }
  df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9' | grep . || echo 0
}
detect_avx2() {
  [ -n "${TOOLSAI_CHECK_AVX2:-}" ] && { echo "$TOOLSAI_CHECK_AVX2"; return; }
  grep -c -m1 avx2 /proc/cpuinfo 2>/dev/null | head -1 || echo 0
}
detect_docker() {
  [ -n "${TOOLSAI_CHECK_DOCKER:-}" ] && { echo "$TOOLSAI_CHECK_DOCKER"; return; }
  command -v docker >/dev/null 2>&1 && echo 1 || echo 0
}
detect_virt() {
  [ -n "${TOOLSAI_CHECK_VIRT:-}" ] && { echo "$TOOLSAI_CHECK_VIRT"; return; }
  systemd-detect-virt 2>/dev/null || echo unknown
}
detect_ports() {
  [ -n "${TOOLSAI_CHECK_PORTS+x}" ] && { echo "$TOOLSAI_CHECK_PORTS"; return; }
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -nu | tr '\n' ' '
  fi
}

# Уровень по ресурсам: min / mid / full / none
level_of() { # cores mem disk
  local c=$1 m=$2 d=$3
  if [ "$c" -ge $FUL_CORES ] && [ "$m" -ge $FUL_MEM ] && [ "$d" -ge $FUL_DISK ]; then echo full
  elif [ "$c" -ge $MID_CORES ] && [ "$m" -ge $MID_MEM ] && [ "$d" -ge $MID_DISK ]; then echo mid
  elif [ "$c" -ge $MIN_CORES ] && [ "$m" -ge $MIN_MEM ] && [ "$d" -ge $MIN_DISK ]; then echo min
  else echo none; fi
}
level_name() { case $1 in min) echo "минимум";; mid) echo "средний";; full) echo "с запасом";; *) echo "ниже минимума";; esac; }

levels_text() { # cores|mem|disk — пороги текущего режима
  local k=$1 a b c
  case $k in cores) a=$MIN_CORES; b=$MID_CORES; c=$FUL_CORES;; mem) a=$MIN_MEM; b=$MID_MEM; c=$FUL_MEM;; disk) a="+$MIN_DISK"; b="+$MID_DISK"; c="+$FUL_DISK";; esac
  if [ "$MODE" = svc ]; then echo "$a / $b"; else echo "$a / $b / $c"; fi
}

mark() { # ok|warn|fail text
  case $1 in ok) printf '  ✅ %s\n' "$2";; warn) printf '  ⚠  %s\n' "$2";; fail) printf '  ❌ %s\n' "$2";; esac
}

main() {
  if [ "${1:-}" = "--services-only" ]; then
    MODE=svc
    MIN_CORES=$SVC_MIN_CORES; MIN_MEM=$SVC_MIN_MEM; MIN_DISK=$SVC_MIN_DISK
    MID_CORES=$SVC_MID_CORES; MID_MEM=$SVC_MID_MEM; MID_DISK=$SVC_MID_DISK
    FUL_CORES=999; FUL_MEM=9999; FUL_DISK=9999
  fi
  local cores mem disk avx2 docker virt ports lvl missing=() warns=()
  cores=$(detect_cores); mem=$(detect_mem_gb); disk=$(detect_disk_gb)
  avx2=$(detect_avx2); docker=$(detect_docker); virt=$(detect_virt); ports=$(detect_ports)
  [ "$avx2" -gt 0 ] 2>/dev/null && avx2=1 || avx2=0

  echo "Tools AI — проверка сервера (toolsai_check.sh $VERSION). Скрипт только читает."
  echo
  if [ "$MODE" = svc ]; then
    echo "Режим: отдельная ВМ только под сервисы (Битрикс24 на другой ВМ)."
    echo "Ресурсы (нужно для минимума / среднего):"
  else
    echo "Режим: Битрикс24 и сервисы на одной ВМ."
    echo "Ресурсы (нужно для минимума / среднего / запаса):"
  fi
  if [ "$cores" -ge $MIN_CORES ]; then mark ok "Ядра: $cores ($(levels_text cores))"; else mark fail "Ядра: $cores (минимум $MIN_CORES)"; missing+=("ядра: нужно минимум $MIN_CORES, есть $cores"); fi
  if [ "$mem" -ge $MIN_MEM ]; then mark ok "Память: $mem ГБ ($(levels_text mem))"; else mark fail "Память: $mem ГБ (минимум $MIN_MEM)"; missing+=("память: нужно минимум $MIN_MEM ГБ, есть $mem"); fi
  if [ "$disk" -ge $MIN_DISK ]; then mark ok "Диск, свободно: $disk ГБ ($(levels_text disk))"; else mark fail "Диск, свободно: $disk ГБ (нужно +$MIN_DISK сверх Битрикса)"; missing+=("диск: нужно минимум +$MIN_DISK ГБ свободно, есть $disk"); fi
  if [ "$avx2" = 1 ]; then mark ok "Процессор: AVX2 есть"; else mark fail "Процессор: AVX2 нет (модели не запустятся)"; missing+=("процессор без AVX2: другой хост или тип процессора"); fi

  echo
  echo "Окружение:"
  if [ "$docker" = 1 ]; then mark ok "Docker: установлен"; else mark warn "Docker: не найден (нужен для своих сервисов; можно поставить)"; warns+=("docker не установлен"); fi
  case $virt in
    lxc) mark warn "Виртуализация: lxc — на хосте нужны nesting=1 и keyctl=1 (подтвердить у администратора хоста)"; warns+=("lxc: nesting=1, keyctl=1");;
    kvm|none) mark ok "Виртуализация: $virt";;
    *) mark warn "Виртуализация: $virt";;
  esac
  [ -n "$ports" ] && echo "  ℹ  Занятые порты (TCP): $ports"

  lvl=$(level_of "$cores" "$mem" "$disk"); [ "$avx2" = 1 ] || lvl=none
  echo
  echo "Уровень по ресурсам: $(level_name "$lvl")"
  if [ ${#missing[@]} -eq 0 ]; then
    echo "Итог: готово"
  else
    local IFS=';'; echo "Итог: не хватает: ${missing[*]}"
  fi
  [ ${#warns[@]} -gt 0 ] && { local IFS=';'; echo "Проверить: ${warns[*]}"; }

  local ok=0; [ ${#missing[@]} -eq 0 ] && ok=1
  echo
  echo "Строка для отправки нам (без имён, адресов и ключей):"
  echo "TAI1;mode=$MODE;cpu=$cores;mem=$mem;disk=$disk;avx2=$avx2;docker=$docker;virt=$virt;level=$lvl;ok=$ok"
}

# Выполняется только при запуске файла, а не при source (тесты).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
