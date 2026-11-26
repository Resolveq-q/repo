#!/bin/sh
# gettools.sh — установка сетевых / OSINT-утилит на джейлбрейкнутый iPhone.
#
# ВАЖНО: ставит только те пакеты, которые есть в подключённых у тебя источниках.
# Чего нет — печатает в отчёте как SKIP, ничего не ломая.
#
# ЗАПУСК (в NewTerm, от root):
#   curl -fsSL https://resolveq-q.github.io/repo/tools/gettools.sh -o /tmp/gettools.sh
#   sh /tmp/gettools.sh            # базовый набор
#   sh /tmp/gettools.sh --osint    # + python-инструменты OSINT (нужен python3)
#
# Только для собственных устройств и сетей. Скан чужой сети — статья.

JB=""
[ -d /var/jb ] && JB="/var/jb"
PATH="$JB/usr/bin:$JB/usr/sbin:$JB/bin:$JB/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

BATCH=0
WITH_OSINT=0
for a in "$@"; do
  case "$a" in
    --osint) WITH_OSINT=1 ;;
    --batch) BATCH=1 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '%s\n' "$*"; }

say "== префикс: ${JB:-/ (rootful)}   архитектура: $(dpkg --print-architecture 2>/dev/null)"

# ---- 0. Обновление индексов ------------------------------------------------
say ""
say "== apt-get update (ошибки отдельных источников не критичны)"
apt-get update 2>&1 | tail -25

# ---- 1. Список пакетов ----------------------------------------------------
# Имя пакета в Debian/Procursus | короткое имя для отчёта
PKGS="
netcat-openbsd|nc
socat|socat
nmap|nmap
tcpdump|tcpdump
ngrep|ngrep
whois|whois
bind9-dnsutils|dig/host
dnsutils|dig/host
net-tools|ifconfig/netstat
iproute2|ip
procps|ps/top
htop|htop
curl|curl
wget|wget
git|git
jq|jq
openssl|openssl
gnupg|gpg
rsync|rsync
unzip|unzip
zip|zip
file|file
less|less
nano|nano
vim|vim
tmux|tmux
lsof|lsof
python3|python3
python3-pip|pip3
perl|perl
libimage-exiftool-perl|exiftool
exiftool|exiftool
openssh|ssh
openssh-server|sshd
"

say ""
say "== ставлю пакеты (по одному, чтобы один сбой не сорвал всё)"
OK=""; SKIP=""; FAIL=""
echo "$PKGS" | while IFS='|' read -r pkg label; do
  [ -z "$pkg" ] && continue
  if have "$label" 2>/dev/null; then
    say "   уже есть   $pkg"
    continue
  fi
  if ! apt-cache show "$pkg" >/dev/null 2>&1; then
    say "   SKIP       $pkg  (нет в источниках)"
    continue
  fi
  if apt-get install -y --no-install-recommends "$pkg" >/tmp/gt_$pkg.log 2>&1; then
    say "   OK         $pkg"
  else
    say "   FAIL       $pkg  (см. /tmp/gt_$pkg.log)"
  fi
done

# ---- 2. Что в итоге есть --------------------------------------------------
say ""
say "== что теперь доступно"
for c in nc ncat socat nmap tcpdump ngrep whois dig host ifconfig netstat ip ps top \
         htop curl wget git jq openssl gpg rsync unzip file less nano vim tmux lsof \
         python3 pip3 perl ssh sshd exiftool; do
  if have "$c"; then say "   ✓ $c  →  $(command -v "$c")"; fi
done

# ---- 3. OSINT через pip (по флагу) ----------------------------------------
if [ "$WITH_OSINT" = "1" ]; then
  say ""
  say "== python-инструменты OSINT"
  if have pip3; then
    pip3 install --upgrade pip >/dev/null 2>&1
    for m in "sherlock-project" "holehe" "socialscan" "h8mail" "dnspython" "shodan"; do
      if pip3 install --no-input "$m" >"/tmp/pip_$m.log" 2>&1; then
        say "   OK   $m"
      else
        say "   FAIL $m (см. /tmp/pip_$m.log — на iOS часть пакетов не собирается)"
      fi
    done
  else
    say "   pip3 нет — сначала поставь python3 (см. выше)"
  fi
fi

say ""
say "== дальше"
say "   nmap -sn 192.168.1.0/24        # кто в моей сети (только своя!)"
say "   nmap -sT -F 192.168.1.1        # быстрый TCP-скан своего роутера"
say "   tcpdump -i en0 -n -c 20        # снуснить 20 пакетов своего трафика"
say "   dig +short example.com; whois example.com"
say "   exiftool photo.jpg             # метаданные фото (OSINT)"
say "   ssh user@host                  # нормальный способ: считать на ПК/сервере"
say ""
say "Тяжёлое (полный nmap по /16, sqlmap, hashcat) на A10 греть и разряжать телефон —"
say "лучше запускать с телефона по ssh на компьютер."
