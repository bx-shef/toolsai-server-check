#!/usr/bin/env bash
# Tools AI — проверка сервера. Только читает, ничего не меняет и не отправляет.
# Запуск: curl -fsSL https://github.com/bx-shef/toolsai-server-check/releases/latest/download/toolsai_check.sh | bash
# Пороги — из системных требований Tools AI: минимум, средний, с запасом.

VERSION="1.1.4"

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

# Строка проверки: статус, что проверено, найдено, норма; при проблеме — что сделать.
# Статусы: ✓ в порядке, ⚠ стоит проверить, ✗ не хватает.
check_line() { # ok|warn|fail "что проверено" "найдено" "норма" "что сделать"
  local sign
  case $1 in ok) sign="✓";; warn) sign="⚠";; *) sign="✗";; esac
  printf '  %s %s: %s (норма %s)\n' "$sign" "$2" "$3" "$4"
  [ "$1" != ok ] && [ -n "${5:-}" ] && printf '      → %s\n' "$5"
}

main() {
  if [ "${1:-}" = "--services-only" ]; then
    MODE=svc
    MIN_CORES=$SVC_MIN_CORES; MIN_MEM=$SVC_MIN_MEM; MIN_DISK=$SVC_MIN_DISK
    MID_CORES=$SVC_MID_CORES; MID_MEM=$SVC_MID_MEM; MID_DISK=$SVC_MID_DISK
    FUL_CORES=999; FUL_MEM=9999; FUL_DISK=9999
  fi
  local cores mem disk avx2 docker virt ports lvl todo=() warns=()
  cores=$(detect_cores); mem=$(detect_mem_gb); disk=$(detect_disk_gb)
  avx2=$(detect_avx2); docker=$(detect_docker); virt=$(detect_virt); ports=$(detect_ports)
  [ "$avx2" -gt 0 ] 2>/dev/null && avx2=1 || avx2=0

  echo "Tools AI — проверка сервера (toolsai_check.sh $VERSION). Скрипт только читает, ничего не меняет и не отправляет."
  echo
  if [ "$MODE" = svc ]; then
    echo "Режим: отдельная ВМ только под сервисы (Битрикс24 на другой ВМ)."
  else
    echo "Режим: Битрикс24 и сервисы на одной ВМ."
  fi
  echo "Знаки: ✓ в порядке, ⚠ стоит проверить, ✗ нужно исправить."
  echo
  echo "Ресурсы (норма: минимум / средний$( [ "$MODE" = svc ] || echo ' / запас')):"
  if [ "$cores" -ge $MIN_CORES ]; then
    check_line ok "Ядра процессора" "$cores" "$(levels_text cores)"
  else
    check_line fail "Ядра процессора" "$cores" "от $MIN_CORES" "добавьте ядра виртуальной машине или возьмите сервер мощнее"
    todo+=("ядра: есть $cores, нужно от $MIN_CORES")
  fi
  if [ "$mem" -ge $MIN_MEM ]; then
    check_line ok "Память" "$mem ГБ" "$(levels_text mem)"
  else
    check_line fail "Память" "$mem ГБ" "от $MIN_MEM ГБ" "увеличьте память виртуальной машины"
    todo+=("память: есть $mem ГБ, нужно от $MIN_MEM ГБ")
  fi
  if [ "$disk" -ge $MIN_DISK ]; then
    check_line ok "Свободный диск" "$disk ГБ" "$(levels_text disk) ГБ сверх Битрикса"
  else
    check_line fail "Свободный диск" "$disk ГБ" "от +$MIN_DISK ГБ сверх Битрикса" "освободите место или расширьте диск"
    todo+=("диск: свободно $disk ГБ, нужно от $MIN_DISK ГБ")
  fi
  if [ "$avx2" = 1 ]; then
    check_line ok "Процессор, AVX2" "есть" "нужна поддержка AVX2"
  else
    check_line fail "Процессор, AVX2" "нет — модели не запустятся" "нужна поддержка AVX2" "включите передачу возможностей процессора виртуальной машине (тип CPU host) или смените хост"
    todo+=("процессор без AVX2: смените тип процессора ВМ или хост")
  fi

  echo
  echo "Окружение:"
  if [ "$docker" = 1 ]; then
    check_line ok "Docker" "установлен" "должен быть для своих сервисов"
  else
    check_line warn "Docker" "не найден" "нужен для своих сервисов" "установите Docker (если свои сервисы не нужны — можно пропустить)"
    warns+=("Docker не установлен: нужен, если запускаете свои сервисы")
  fi
  case $virt in
    lxc) check_line warn "Виртуализация" "lxc" "в LXC нужны nesting=1 и keyctl=1" "включите nesting=1 и keyctl=1 в настройках контейнера на хосте"
         warns+=("lxc: включите nesting=1 и keyctl=1 на хосте");;
    kvm|none) check_line ok "Виртуализация" "$virt" "kvm, none или другая полная";;
    *) check_line warn "Виртуализация" "$virt" "определить тип не удалось" "если это LXC — нужны nesting=1 и keyctl=1 на хосте"
       warns+=("тип виртуализации не определён: если это LXC — нужны nesting=1 и keyctl=1");;
  esac
  [ -n "$ports" ] && echo "  ℹ Занятые порты (TCP): $ports. Порты сервисов не должны пересекаться с ними."

  lvl=$(level_of "$cores" "$mem" "$disk"); [ "$avx2" = 1 ] || lvl=none
  echo
  echo "Уровень по ресурсам: $(level_name "$lvl")"
  echo
  echo "=== Сводка ==="
  if [ ${#todo[@]} -eq 0 ]; then
    echo "Итог: готово — сервер подходит для Tools AI."
  else
    echo "Итог: не готов к Tools AI. Исправьте:"
    local t; for t in "${todo[@]}"; do echo "  ✗ $t"; done
  fi
  if [ ${#warns[@]} -gt 0 ]; then
    echo "Проверьте:"
    local w; for w in "${warns[@]}"; do echo "  ⚠ $w"; done
  fi
}

# Выполняется только при запуске файла, а не при source (тесты).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
