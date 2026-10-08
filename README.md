
<div align="center">

# 🚀 DNS Manager

### Надёжный DNS-контур для OpenWrt

<a href="https://github.com/PoTuStoronu222/DNS-Manager">
  <img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&size=21&duration=2600&pause=900&color=2F81F7&center=true&vCenter=true&width=840&lines=Hybrid+DoH+%E2%80%A2+Watchdog+%E2%80%A2+native+LuCI;Real-time+DNS+checks+%E2%80%A2+safe+apply+%E2%80%A2+rollback;OpenWrt+DNS+without+unnecessary+changes" alt="DNS Manager animation">
</a>

<br>

[![OpenWrt](https://img.shields.io/badge/OpenWrt-ready-00B5E2?style=for-the-badge&logo=openwrt&logoColor=white)](https://openwrt.org/)
[![POSIX sh](https://img.shields.io/badge/POSIX-sh-4EAA25?style=for-the-badge)](https://pubs.opengroup.org/onlinepubs/9699919799/)
[![Hybrid DoH](https://img.shields.io/badge/Hybrid-DoH-FF6D00?style=for-the-badge)](#-hybrid-doh)
[![Native LuCI](https://img.shields.io/badge/native-LuCI-5E5CE6?style=for-the-badge)](#-native-luci)
[![Watchdog](https://img.shields.io/badge/Watchdog-self--healing-00A67E?style=for-the-badge)](#-watchdog)
[![Rollback](https://img.shields.io/badge/transactions-rollback-7C4DFF?style=for-the-badge)](#-безопасное-применение)

<br>

[![GitHub stars](https://img.shields.io/github/stars/PoTuStoronu222/DNS-Manager?style=flat-square&logo=github)](https://github.com/PoTuStoronu222/DNS-Manager/stargazers)
[![GitHub last commit](https://img.shields.io/github/last-commit/PoTuStoronu222/DNS-Manager?style=flat-square)](https://github.com/PoTuStoronu222/DNS-Manager/commits/main)

</div>

---

> **DNS Manager** управляет локальным DNS-контуром OpenWrt через <code>dnsmasq</code> и <code>https-dns-proxy</code>, проверяет DoH-серверы реальными запросами, сохраняет выбранные категории и заменяет неисправные DNS только там, где это разрешено конфигурацией.

<div align="center">

### 💡 Главный принцип

**Работающий DNS не меняется без причины.**

</div>

## 📖 Содержание

- [✨ Возможности](#-возможности)
- [🏗️ Архитектура](#️-архитектура)
- [⚡ Установка](#-установка)
- [📦 Совместимость](#-совместимость)
- [🚀 Первый запуск](#-первый-запуск)
- [🧭 Как это работает](#-как-это-работает)
- [🧿 Категории DNS](#-категории-dns)
- [🔌 Hybrid DoH](#-hybrid-doh)
- [🐕 Watchdog](#-watchdog)
- [🔍 Проверка DNS](#-проверка-dns)
- [🛡️ Принудительный DNS](#️-принудительный-dns)
- [🕐 NTP и Bootstrap](#-ntp-и-bootstrap)
- [💾 Безопасное применение](#-безопасное-применение)
- [🖥️ Native LuCI](#️-native-luci)
- [🤝 Совместимость с другими сервисами](#-совместимость-с-другими-сервисами)
- [🗑️ Удаление](#️-удаление)
- [⚠️ Ограничения](#️-ограничения)
- [🧪 Диагностика](#-диагностика)

---

## ✨ Возможности

| | Возможность | |
|---|---|---|
| 🚀 | **Hybrid DoH** | Локальный пул DoH через <code>https-dns-proxy</code> |
| ⚖️ | **Балансировка** | Одновременный опрос рабочих DNS |
| 🧿 | **Категории** | Каждый рабочий слот сохраняет своё назначение |
| 🐕 | **Watchdog** | Проверка и точечная замена неисправного DNS |
| 🇷🇺 | **RU-контур** | Отдельная работа с <code>.ru</code>, <code>.su</code>, <code>.рф</code> |
| 🛡️ | **Принудительный DNS** | Управление своим контуром и обнаружение внешнего перехвата |
| 🧠 | **DNS Cache** | Тонкая настройка локального кэша |
| 🕐 | **NTP** | Отдельные серверы точного времени |
| 🔎 | **Bootstrap DNS** | Начальное разрешение DoH-хостов |
| 💾 | **Transactions** | Snapshot → Apply → Verify → Rollback |
| 🔐 | **Ownership** | Не перезаписывать чужие конфигурации |
| 🌐 | **Native LuCI** | Управление через стандартное LuCI |
| 🧰 | **SSH** | Единый backend для консоли и LuCI |

---

## 🏗️ Архитектура

~~~mermaid
flowchart LR
    C["🖥️ LAN-клиенты"] --> D["dnsmasq :53"]
    D --> P["DoH-пул"]
    P --> H["https-dns-proxy"]
    H --> I["🌐 Internet"]

    RU["🇷🇺 RU DNS"] --> D

    S["SSH"] --> B["DNS Manager backend"]
    L["native LuCI"] --> RPC["rpcd"]
    RPC --> B

    W["🐕 Watchdog"] --> T["реальная проверка"]
    T --> R["точечное восстановление"]

    CAT["📚 DNS-каталог"] --> B
~~~

### Один backend

~~~text
               ┌─────────────────────┐
               │     DNS Manager     │
               └──────────┬──────────┘
                          │
             ┌────────────┴────────────┐
             │                         │
            SSH                       LuCI
             │                         │
             └────────────┬────────────┘
                          ↓
                   единый backend
                          │
          ┌───────────────┼───────────────┐
          ↓               ↓               ↓
       dnsmasq      https-dns-proxy    Watchdog
~~~

LuCI не дублирует DNS-логику. Он использует тот же backend.

---

## ⚡ Установка

### Backend

~~~sh
wget -O /usr/bin/dns-manager \
  https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager.sh

chmod +x /usr/bin/dns-manager
dns-manager
~~~

### Native LuCI

~~~sh
sh <(wget -qO - \
  https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh)
~~~

После установки:

**LuCI → Службы → DNS Manager**

> [!NOTE]
> Native LuCI устанавливается отдельно и не заменяет основной backend.

---

## 📦 Совместимость

| Компонент | Поддержка / назначение |
|---|---|
| **OpenWrt** | основная платформа |
| **dnsmasq** | локальный DNS для клиентов |
| **https-dns-proxy** | локальные DoH-инстансы |
| **opkg / apk** | установка системных пакетов |
| **fw3 / fw4** | определение используемого firewall backend |
| **curl / wget / uclient-fetch** | загрузка и сетевые проверки |
| **CA-сертификаты** | TLS |
| **dig** | диагностика |

Manager рассчитан на реальные OpenWrt-сборки и старается использовать то, что уже присутствует в системе, вместо создания лишнего отдельного стека.

---

## 🚀 Первый запуск

При первом запуске менеджер сначала читает систему:

~~~text
DISCOVER
   ↓
каталог DNS
   ↓
конфигурация
   ↓
возможности роутера
   ↓
карта текущего состояния
~~~

> [!IMPORTANT]
> **Первый запуск не переписывает существующий cron.**

Это особенно важно для уже настроенного роутера. Изменения Watchdog применяются только после явного включения нужного режима и прохождения штатной логики миграции.

---

## 🧭 Как это работает

Главный цикл изменения:

~~~text
DISCOVER
   ↓
PLAN
   ↓
SNAPSHOT
   ↓
APPLY
   ↓
VERIFY
   ├── ✅ OK
   └── ❌ ERROR
            ↓
        ROLLBACK
~~~

Менеджер сначала определяет фактическое состояние, затем изменяет только нужную часть конфигурации и после этого проверяет результат.

---

## 🧿 Категории DNS

DNS-каталог группирует серверы по назначению:

| Категория | Назначение |
|---|---|
| <code>bypass</code> | обход региональных и DNS-ограничений |
| <code>clean</code> | обычный публичный DNS |
| <code>security</code> | защита от вредоносных доменов и фишинга |
| <code>privacy</code> | решения с упором на приватность |
| <code>adblock</code> | блокировка рекламы и трекеров |
| <code>family</code> | семейная фильтрация |
| <code>regional</code> | региональные сценарии |

### Главное правило категории

~~~text
bypass
  ↓
DNS сломался
  ↓
ищем replacement только в bypass
  ↓
проверяем
  ↓
применяем
~~~

> [!IMPORTANT]
> **Категория ограничивает замену. Она не заставляет менять рабочий DNS.**

---

## 🔌 Hybrid DoH

Основной контур строится из локальных экземпляров <code>https-dns-proxy</code>.

~~~text
                    dnsmasq
                       │
          ┌────────────┼────────────┐
          ↓            ↓            ↓
       DoH #1        DoH #2       DoH #N
          │            │            │
          └────────────┼────────────┘
                       ↓
                   HTTPS / DoH
                       ↓
                    Internet
~~~

Каждый выбранный DNS проверяется отдельно.

Балансировка и маршрутизация применяются только согласно активной конфигурации.

---

## 🐕 Watchdog

Watchdog не делает вывод «DNS умер» только по наличию процесса или по одному неудачному запросу.

~~~mermaid
flowchart TD
    A["⏱️ Плановая проверка"] --> B["🔍 Реальный DNS/DoH запрос"]
    B --> C{"Ответ получен?"}
    C -->|Да| D["✅ Ничего не менять"]
    C -->|Нет| E["🔁 Повторная проверка"]
    E --> F{"Отказ подтверждён?"}
    F -->|Нет| D
    F -->|Да| G["🧿 Та же категория"]
    G --> H["🔬 Проверка кандидата"]
    H --> I{"Кандидат рабочий?"}
    I -->|Нет| G
    I -->|Да| J["🛠️ Точечная замена"]
    J --> K["✅ VERIFY"]
    K -->|Ошибка| L["↩️ ROLLBACK"]
~~~

Watchdog:

- проверяет реальный DNS;
- отсеивает временный сбой;
- ищет замену только в разрешённой категории;
- проверяет кандидата до применения;
- не трогает работающий DNS;
- после восстановления снова проверяет контур;
- при ошибке откатывает изменение.

---

## 🔍 Проверка DNS

Проверяется не только наличие TCP-соединения.

Для DoH учитываются:

- разрешение имени;
- HTTPS/TLS;
- ответ сервера;
- тип содержимого DoH;
- корректность DNS-ответа;
- время ответа;
- пригодность сервера для рабочего контура.

То есть «endpoint открывается» ещё не означает «DNS пригоден».

---

## 🛡️ Принудительный DNS

DNS Manager различает собственный DNS-перехват и внешний механизм.

Состояние может быть отображено как:

~~~text
DNS Manager
внешний сервис
ДРУГОЕ • Steer
DNS Manager + внешний
выключен
~~~

При наличии внешнего контура менеджер сначала определяет владельца и состояние, а не молча перезаписывает чужие правила.

### Steer

Если DNS-маршрутом управляет Steer, DNS Manager учитывает это при проверке состояния и не создаёт поверх него вторую независимую схему перенаправления.

---

## 🕐 NTP и Bootstrap

### Bootstrap DNS

Bootstrap используется для первоначального разрешения DoH-хостов и отделён от рабочего DNS-пула.

~~~text
bootstrap
   ↓
IP DoH-сервера
   ↓
HTTPS / DoH
   ↓
рабочий DNS
~~~

### NTP

Точное время необходимо для TLS.

Менеджер работает с системным <code>sysntpd</code> и может использовать NTP-серверы по IP для bootstrap-сценариев.

---

## 💾 Безопасное применение

Менеджер использует транзакционный подход:

~~~text
┌──────────────┐
│   SNAPSHOT   │
└──────┬───────┘
       ↓
┌──────────────┐
│     APPLY    │
└──────┬───────┘
       ↓
┌──────────────┐
│    VERIFY    │
└──────┬───────┘
   ┌───┴────┐
   ↓        ↓
  OK       ERROR
   │        │
   ↓        ↓
 commit  rollback
~~~

Кроме этого, изменяющие операции защищены runtime lock, чтобы параллельные действия из SSH и LuCI не конфликтовали.

---

## 🖥️ Native LuCI

**LuCI → Службы → DNS Manager**

~~~text
DNS Manager
├── Дашборд
├── DNS over HTTPS
├── DNS
├── Профили
├── Настройки
├── Каталог
├── Тест
└── Журнал
~~~

### Дашборд

Показывает фактическое состояние системы и DNS-контура:

- выбранный профиль;
- рабочие DNS;
- категории;
- Watchdog;
- принудительный DNS;
- DNS cache;
- NTP;
- состояние компонентов;
- последнее тестирование;
- каталог.

### Настройки

Управляются основные параметры Watchdog, DNS cache, NTP и дополнительных DNS-модулей.

### Каталог и тесты

Каталог можно проверять отдельно от рабочего набора.

Фоновая проверка имеет собственное состояние и не должна менять конфигурацию просто из-за открытия страницы.

---

## 🤝 Совместимость с другими сервисами

DNS Manager рассчитан на роутер, где уже могут работать другие сетевые инструменты.

Особенно важно различать:

- собственную конфигурацию;
- внешний DNS-контур;
- Steer;
- свои firewall-правила;
- сторонние изменения.

### Не должны быть без причины затронуты

- WireGuard;
- VPN;
- Zapret;
- Steer;
- чужие DoH-конфигурации;
- сторонние firewall-правила.

---

## 🗑️ Удаление

Удаление DNS Manager выключает его функции и очищает созданные им настройки и службы.

Удаляются только принадлежащие Manager:

- выбранные DNS Manager DNS и связанные настройки;
- собственные dnsmasq/firewall-объекты;
- watchdog и служебные задания;
- native LuCI-компоненты;
- пакеты, которые сам Manager установил.

Исторический backup для удаления не используется. Сторонние сервисы и настройки не удаляются.

> [!IMPORTANT]
> Удаление DNS Manager не восстанавливает старую конфигурацию роутера и не является сбросом OpenWrt.

---

## ⚠️ Ограничения

DNS Manager работает на **уровне DNS**.

Он подходит для задач, связанных с DNS-ответами, DNS-фильтрацией, доступностью DNS-провайдера и локальным DoH-контуром.

Но он не является:

- VPN;
- прокси;
- DPI-обходчиком;
- универсальным туннелем.

Для более сложных сетевых сценариев DNS Manager может работать рядом с другими инструментами, например Steer или Zapret.

---

## 🧪 Диагностика

### Состояние принудительного DNS

~~~sh
/usr/bin/dns-manager --force-state
~~~

### Локальный DNS

~~~sh
nslookup example.com 127.0.0.1
~~~

### Локальный DoH-инстанс

~~~sh
dig @127.0.0.1 -p 5053 example.com A +short
~~~

> <code>5053</code> — пример. Фактический порт смотрите в карте состояния DNS Manager или LuCI.

### Системные службы

~~~sh
/etc/init.d/dnsmasq status
/etc/init.d/sysntpd status
~~~

### Лог

~~~sh
logread | grep -i dns-manager
~~~

---

## 🧩 Структура проекта

~~~text
dns-manager.sh
    └── основной backend

dns-manager-luci.sh
    └── native LuCI + rpcd

catalogs/
    └── отдельный DNS-каталог

tests/
    └── регрессионные проверки
~~~

Каталог вынесен отдельно, чтобы большой набор DNS не раздувал основной shell-код и мог обновляться независимо.

---

<div align="center">

### 🚀 DNS Manager

**Hybrid DoH · Watchdog · native LuCI · safe DNS management**

Made with ❤️ for the OpenWrt community

</div>
