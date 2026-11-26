#!/bin/sh
# tune.sh — аудит и безопасная «уборка» джейлбрейкнутого iPhone.
#
# ЧТО ДЕЛАЕТ: только читает состояние и чистит кеши пакетного менеджера.
# Ничего не удаляет из системы, не выключает демоны, не меняет настройки.
#
# ЗАПУСК (в NewTerm, от root):
#   curl -fsSL https://resolveq-q.github.io/repo/tools/tune.sh -o /tmp/tune.sh
#   sh /tmp/tune.sh
#
# Всё, что касается реальной экономии батареи, делается в Настройках iOS —
# скрипт в конце печатает чеклист.

JB=""
[ -d /var/jb ] && JB="/var/jb"
PATH="$JB/usr/bin:$JB/usr/sbin:$JB/bin:$JB/sbin:$PATH"
export PATH

line() { printf '%s\n' "------------------------------------------------------------"; }
have() { command -v "$1" >/dev/null 2>&1; }

line; echo "1. УСТРОЙСТВО"; line
[ -f /System/Library/CoreServices/SystemVersion.plist ] && \
  plutil -p /System/Library/CoreServices/SystemVersion.plist 2>/dev/null | \
  grep -E 'ProductVersion|ProductBuildVersion' | tr -d ' "'
echo "архитектура dpkg: $(dpkg --print-architecture 2>/dev/null)"
echo "ядро: $(uname -r)  устройство: $(uname -n)"
echo "префикс джейлбрейка: ${JB:-/(rootful)}"

line; echo "2. МЕСТО НА ДИСКЕ"; line
df -h / 2>/dev/null | tail -2
[ -n "$JB" ] && df -h "$JB" 2>/dev/null | tail -1

line; echo "3. АККУМУЛЯТОР"; line
if have ioreg; then
  ioreg -rn AppleSmartBattery 2>/dev/null | \
    grep -E '"(CycleCount|DesignCapacity|AppleRawMaxCapacity|Temperature|Voltage)"' | \
    sed 's/^[[:space:]]*//' || echo "ioreg не отдал данные (нужен root)"
else
  echo "ioreg недоступен"
fi
echo "Здоровье также смотри в: Настройки → Аккумулятор → Состояние аккумулятора"

line; echo "4. КТО ЕСТ CPU (топ-12)"; line
ps aux 2>/dev/null | sort -k3 -nr | head -13 | awk '{printf "%-6s %5s%% %5s%% %s\n", $1, $3, $4, $11}' 2>/dev/null \
  || echo "ps недоступен"

line; echo "5. ТВИКИ (инъекции)"; line
for d in "$JB/Library/MobileSubstrate/DynamicLibraries" /Library/MobileSubstrate/DynamicLibraries; do
  [ -d "$d" ] || continue
  n=$(ls "$d"/*.dylib 2>/dev/null | wc -l | tr -d ' ')
  echo "$d — $n dylib"
  if [ "$n" -gt 0 ]; then
    ls -S "$d"/*.dylib 2>/dev/null | head -12 | while read -r f; do
      printf '   %6s  %s\n' "$(du -h "$f" 2>/dev/null | cut -f1)" "$(basename "$f")"
    done
  fi
done
echo "Ориентир: 10-15 активных твиков — норма, 40+ заметно бьют по батарее и стабильности."

line; echo "6. РЕПОЗИТОРИИ"; line
for f in "$JB"/etc/apt/sources.list "$JB"/etc/apt/sources.list.d/*; do
  [ -f "$f" ] || continue
  echo "== $f"
  grep -hE '^(deb|Types|URIs|Suites)' "$f" 2>/dev/null | sed 's/^/   /'
done
cnt=$(cat "$JB"/etc/apt/sources.list "$JB"/etc/apt/sources.list.d/* 2>/dev/null | grep -cE '^(deb |URIs:)')
echo "всего источников: $cnt (каждый лишний репозиторий замедляет apt update)"

line; echo "7. УБОРКА КЕШЕЙ"; line
before=$(du -sh "$JB/var/cache/apt" 2>/dev/null | cut -f1)
apt-get clean 2>/dev/null && echo "apt-get clean: готово (было ${before:-?})"
rm -rf /tmp/*.deb 2>/dev/null

line; echo "8. ЧЕКЛИСТ НАСТРОЕК (сделай руками, это даёт больше всего)"; line
cat <<'EOF'
[ ] Аккумулятор → Состояние аккумулятора: если < 80% — только замена, твики не помогут
[ ] Основные → Обновление контента → выключить всё лишнее (или полностью)
[ ] Основные → Обновление ПО → Автообновление → выключить
[ ] Приватность → Аналитика → выключить «Делиться анализом iPhone»
[ ] Приватность → Службы геолокации → Системные службы → оставить минимум
[ ] Wi-Fi → помимо «Ассистента Wi-Fi» также выключить «Авто-вход», «Спрашивать о сетях»
[ ] Основные → AirDrop → «Получать выкл»
[ ] Face ID и код-пароль → «Поднимать для включения» → выкл (меньше датчиков в простое)
[ ] Siri → «Слушать „Привет, Siri“» → выкл
[ ] Уведомления → Значки приложений → выкл (минус постоянные перерисовки)
[ ] Почта → Новые данные → «Вручную»
[ ] Универсальный доступ → Уменьшение прозрачности → ВКЛ (плоско + меньше GPU)
[ ] Универсальный доступ → Уменьшение движения → ВКЛ (быстрее ощущается, меньше анимаций)
[ ] Обои → статичные, без «перспективы»
[ ] Choicy → отключить инъекцию твиков для тяжёлых игр и банковских приложений
[ ] Speedster → сегмент 2 (не 3+): больше — уже не «плавно», а рывками
EOF

line; echo "ГОТОВО. Полный отчёт можно переслать: sh /tmp/tune.sh > /tmp/tune-report.txt"; line
