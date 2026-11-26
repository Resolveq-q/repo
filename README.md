# Мой личный APT-репозиторий для Sileo / Zebra

Свой репозиторий на GitHub Pages. Нужен, чтобы ставить твики, когда обычные
репозитории с телефона не открываются (ошибка **522** от Cloudflare, пустые
списки пакетов и т.п.).

Работает так: `.deb` качаются **на компьютер** (там 522 нет), кладутся в этот
репозиторий, GitHub Actions собирает индекс `Packages`/`Release`, а телефон
забирает файлы уже с `github.io` — быстро и без Cloudflare.

```
debs/                        ← сюда .deb (можно оба варианта: arm и arm64)
repo-tools/gen-repo.py       ← локальная сборка индекса (Windows/Python)
repo-tools/build-repo.sh     ← та же сборка для CI (dpkg-scanpackages)
repo-tools/download-debs.ps1 ← скачать стартовый набор .deb с ПК
repo-tools/find-package.py   ← найти пакет в чужом репо и получить прямую ссылку
.github/workflows/           ← автосборка + деплой на GitHub Pages
```

---

## 1. Быстрый старт (один раз)

### 1.1 Скачать пакеты на ПК

Из корня этой папки:

```powershell
powershell -ExecutionPolicy Bypass -File repo-tools\download-debs.ps1
```

По умолчанию качаются оба варианта сборки (rootful `iphoneos-arm` и rootless
`iphoneos-arm64`) — лишние Sileo просто не покажет. Только нужный вариант:

```powershell
... download-debs.ps1 -Rootless      # если джейлбрейк rootless (/var/jb)
... download-debs.ps1 -Rootful       # если rootful
... download-debs.ps1 -WithTheme     # + тема иконок Morandi
```

### 1.2 Проверить сборку локально

```powershell
python repo-tools\gen-repo.py
```

В папке `_site\` появятся `Release`, `Packages`, `Packages.gz`, `debs\`.
Если скрипт отработал без «Проблемы:» — всё правильно.

### 1.3 Создать репозиторий на GitHub и запушить

1. github.com → **New repository** → имя, например `repo` → **Public**
   (Pages на бесплатном аккаунте работает только с публичным репозиторием) →
   без README/license.
2. В этой папке:

```powershell
git remote add origin https://github.com/ТВОЙ_НИК/repo.git
git push -u origin main
```

Если `git` попросит авторизацию — логин = ник, пароль = **Personal Access
Token** (Settings → Developer settings → Tokens (classic) → `repo` scope),
обычный пароль от аккаунта не подойдёт.

### 1.4 Включить Pages

GitHub → репозиторий → **Settings → Pages → Build and deployment → Source:
GitHub Actions**.
Затем вкладка **Actions** → workflow «Build & Deploy Repo» → **Re-run all jobs**
(или просто сделай любой новый коммит).

Через минуту адрес репозитория:

```
https://ТВОЙ_НИК.github.io/repo/
```

Проверь на ПК, что открываются оба файла:

- `https://ТВОЙ_НИК.github.io/repo/Release`
- `https://ТВОЙ_НИК.github.io/repo/Packages`

### 1.5 Подключить в Sileo / Zebra

Sileo → вкладка **Sources** → **+** → вставить
`https://ТВОЙ_НИК.github.io/repo/` (со слэшем на конце) → **Add Source**.
Zebra → **Sources** → **+** → тот же адрес.

После обновления источников появятся пакеты из `debs/`.

---

## 2. Как добавить ещё пакеты

1. Найти пакет и получить прямую ссылку:

```powershell
python repo-tools\find-package.py https://havoc.app "home bar"
python repo-tools\find-package.py https://repo.chariz.com "gesture"
```

Скрипт покажет имя, версию, архитектуру, размер, пометку `[ПЛАТНЫЙ]` и ссылку на `.deb`.

2. Скачать нужный `.deb` в папку `debs/` (имя файла — любое).
3. `python repo-tools\gen-repo.py` — проверить локально.
4. Коммит и пуш:

```powershell
git add -A
git commit -m "add tweak"
git push
```

GitHub Actions пересоберёт индекс сам. На телефоне — **Refresh** в Sileo/Zebra.

### 2.1 Если с твоего канала файлы не качаются

Из России часть адресов (Cloudflare, havoc.app) отдаёт файлы крайне медленно —
та же причина, по которой на телефоне была ошибка 522. Для таких пакетов есть
`extras.txt`: там строки `URL | имя файла`, и **скачивает их сам GitHub Actions**
(его сеть вне РФ), а не твой компьютер.

Добавь строку в `extras.txt`, сделай `git push` — пакет появится в репозитории
без скачивания у тебя. Битые и недокачанные `.deb` сборка отбрасывает сама и не
падает.

Уже добавлено через `extras.txt`:
- `com.saihgupr.remotecompanion` 4.4.0 — привязка жестов (в т.ч. от статус-бара)
  к системным действиям, чтобы Пункт управления открывался сверху;
- `com.rowandesign.morandi` 1.1.0 — тема иконок под SnowBoard.


---

## 3. Если что-то не работает

| Симптом | Причина / что делать |
|---|---|
| В Sileo «ошибка 522» и на моём репозитории | Actions не отработал или Pages не включён. Открой `https://ТВОЙ_НИК.github.io/repo/Release` в браузере на ПК. 404 → включи Pages / перезапусти workflow |
| Источник добавился, но список пустой | В `debs/` не было `.deb`, либо все `.deb` для другой архитектуры (`iphoneos-arm` vs `iphoneos-arm64`). Проверь в терминале на телефоне: `dpkg --print-architecture` |
| «unmet dependencies» при установке | У пакета есть зависимости (например `preferenceloader`, `mobilesubstrate`, `altlist`). Поставь их тем же способом — положи `.deb` зависимостей в `debs/` |
| Твик поставился, но ничего не изменилось | Скорее всего пакет собран для другой архитектуры/версии iOS. Смотри поле `Depends` в `Packages`: например `firmware (<= 14)` на iOS 15 не заработает |
| Файл больше 100 МБ не пушится | Лимит GitHub на файл. Большие пакеты (крупные темы) лучше не тащить в репозиторий |

Проверка индекса из терминала на телефоне:

```sh
curl -sI https://ТВОЙ_НИК.github.io/repo/Packages
apt-get update
apt-cache policy com.spark.snowboard
```

---

## 4. Важное

- Это **личный** репозиторий: пакеты в нём — чужие файлы, выложенные авторами
  бесплатно. Не добавляй сюда платные твики и не делай репозиторий публичной
  «свалкой» — за это GitHub может снести аккаунт.
- GitHub Pages отдаёт статику без Cloudflare, поэтому именно этот путь и
  обходит 522. Если и `github.io` с телефона не открывается — проблема в сети
  (провайдер/DPI), а не в репозитории.
- После `git push` индекс обновляется ~1 минуту. Sileo иногда кэширует — помогает
  повторный Refresh или перезапуск приложения.
