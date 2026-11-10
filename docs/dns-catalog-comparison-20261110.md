# Аудит публичных DNS — сопоставление с каталогом DNS Manager

Дата: 10 ноября 2026. Источники: пользовательский снимок `dns.quic.best/data.js` (101 провайдер, 198 профилей) и `catalogs/dns-8.7-RU-NOSOCIAL.conf` в `main` (rev.14, 116 DoH-записей).

> **Не результат сетевой проверки.** Сравнение выполнено по точному совпадению DoH URL без завершающего `/`. Два разных URL одного провайдера учитываются как разные адреса. Указанный URL не означает, что это рабочий DNS-over-HTTPS endpoint. Принадлежность оператора и юрисдикция не устанавливаются из названия/региона.

## Итоги

- В исходном каталоге DNS Manager: **116** записей; существующие ID, категории, URL, порядок и ревизию **не меняли**.
- В справочнике сайта: **101** провайдер, **198** профилей, **194** полей DoH URL.
- Есть хотя бы одно точное совпадение DoH URL для **62** провайдеров (99 адресов-профилей).
- **35** провайдеров с DoH не имеют точного совпадения URL в текущем каталоге (не обязательно новые операторы).
- **4** провайдера не имеют DoH URL в справочнике: HiNet DNS, SkyDNS, Level 3, NullsProxy DNS.

## Не совпавшие по точному DoH URL провайдеры — проверять перед добавлением

| № | Провайдер | Раздел источника | DoH URL (пример) | Профилей DoH |
|---:|---|---|---|---:|
| 1 | Alibaba DNS | Глобальные | `https://alidns.com` | 2 |
| 2 | AhaDNS | Приватность | `https://ahadns.com` | 3 |
| 3 | RethinkDNS | Приватность | `https://rethinkdns.com` | 2 |
| 4 | BlahDNS | Приватность | `https://doh-de.blahdns.com/dns-query` | 3 |
| 5 | Shadow DNS | Приватность | `https://dns.shadowvpn.io/dns-query` | 1 |
| 6 | MeatDNS | Семейные | `https://meatdns.com` | 1 |
| 7 | Quad101 | Азия | `https://dns.twnic.tw/dns-query` | 1 |
| 8 | DNSPod (Tencent) | Азия | `https://doh.pub/dns-query` | 2 |
| 9 | Astracat DNS | Обход геоблока | `https://dns.astracat.network/dns-query` | 1 |
| 10 | UncensoredDNS | Европа | `https://anycast.uncensoreddns.org/dns-query` | 2 |
| 11 | TiarAP | Азия | `https://doh.tiarap.org/dns-query` | 4 |
| 12 | Freedom MyDNS | Европа | `https://freedom.mydns.network/dns-query` | 1 |
| 13 | V.recipes | Глобальные | `https://v.recipes/dns-query` | 6 |
| 14 | WeDNS (WeVPN) | Приватность | `https://dns.wevpn.com/dns-query` | 2 |
| 15 | Njalla | Приватность | `https://dns.njal.la/dns-query` | 1 |
| 16 | Ibuki DNS | Северная Америка | `https://ibuki.cgnat.net/dns-query` | 1 |
| 17 | Kernel Error | Европа | `https://dns.kernel-error.de/dns-query` | 1 |
| 18 | Restena | Европа | `https://dnspub.restena.lu/dns-query` | 2 |
| 19 | FoxyFy | Глобальные | `https://dns.foxyfy.net/dns-query` | 8 |
| 20 | JupitrDNS | Глобальные | `https://dns.jupitrdns.com/dns-query` | 1 |
| 21 | Caliph DNS | Азия | `https://dns.caliph.dev/dns-query` | 1 |
| 22 | AS212683 | Европа | `https://dns.as212683.net/dns-query` | 1 |
| 23 | UsablePrivacy | Глобальные | `https://adfree.usableprivacy.net/dns-query` | 1 |
| 24 | DNS over Tor | Азия | `https://hongkong.dnsovertor.cc/dns-query` | 6 |
| 25 | EasyHNS | Европа | `https://dns.easyhns.com/dns-query` | 1 |
| 26 | SEIA DNS | Азия | `https://dns.seia.io/dns-query` | 2 |
| 27 | DeCloudUs | Европа | `https://dns.decloudus.com/dns-query` | 1 |
| 28 | DNSWarden | Глобальные | `https://dns.dnswarden.com/uncensored` | 1 |
| 29 | MarbledFennec | Глобальные | `https://dns.marbledfennec.net/dns-query` | 1 |
| 30 | RabbitDNS | Глобальные | `https://dns.rabbitdns.org/dns-query` | 3 |
| 31 | 360 DNS | Азия | `https://doh.360.cn/dns-query` | 1 |
| 32 | Cloudflare Gateway | Глобальные | `https://frd4wvnobp.cloudflare-gateway.com/dns-query` | 1 |
| 33 | Synology Me | Глобальные | `https://ibksturm.synology.me/dns-query` | 1 |
| 34 | Techomespace | Глобальные | `https://rx.techomespace.com/dns-query` | 1 |
| 35 | Shecan | Обход геоблока | `https://free.shecan.ir/dns-query` | 1 |

Важные совпадения по смыслу, **не** по URL:

- `shecan` в текущем каталоге называется **Zapret DNS** и использует `https://dns.zapret.moe/dns-query`; в справочнике **Shecan** — `https://free.shecan.ir/dns-query`, а **Zapret.moe DNS** — отдельный сервер. Это конфликт исторического ID и отображаемого провайдера. Не менять ID или URL автоматически: сначала проверить, как используются слоты и выбор DNS.
- **AstraCat**: текущий `https://dns.commonnet.work/dns-query`, в справочнике `https://dns.astracat.network/dns-query`. Не заменять без проверки.
- **DNSPod/Tencent**: текущий `https://dns.pub/dns-query`, в справочнике также упоминается `https://doh.pub/dns-query`. Это может быть альтернативный endpoint, а не новый оператор.
- **Mullvad**: публичный DoH закрыт 02.11.2026 согласно объявлению оператора. Наши `mullvad_family` и `mullvad_all` остаются для совместимости с сохранёнными слотами; предупреждение пользователю требуется.

## Предлагаемая организация по назначению (без изменения ID)

| ID категории DNS Manager | Название для LuCI | Что объясняем |
|---|---|---|
| `bypass` | Для геоблока | Специальные ответы для сервисов; это не VPN и не гарантия обхода DPI |
| `clean` | Без фильтрации | Обычный DNS без дополнительных фильтров; не гарантия доступности |
| `security` | От угроз | Вредоносные домены и фишинг; не замена антивирусу |
| `privacy` | Приватность | Политика логов, юрисдикция, пределы DoH |
| `adblock` | Без рекламы | Фильтрация рекламы и трекеров, возможные ложные блокировки |
| `family` | Для семьи | 18+/детские профили, ограничения DNS-фильтрации |
| `gaming` | Игровые DNS | Специальные игровые сервисы; ограниченная область действия |
| `regional` | Для зон .ru | Российские доменные зоны, правила оператора и юрисдикция |
| `custom` | Мои DNS | Пользовательские серверы живут отдельно от встроенного каталога |

Справочник сайта группирует преимущественно по **географии**, а наш DNS Manager — по **роли фильтрации**. Поэтому переносить записи один к одному по разделу источника нельзя: например, международный Cloudflare может быть `clean`, `security` или `family` в зависимости от DoH URL.

## Формулировка предупреждения о РФ

Операторы связи в РФ выполняют применимые требования по ограничению доступа. Требования к конкретному публичному DNS зависят от его правового статуса; нельзя приравнивать каждый частный DNS к оператору связи с ТСПУ. DoH/DoT защищает канал до DNS-оператора, но сам оператор может фильтровать, журналировать или изменять ответы. Географическая категория сама по себе не подтверждает юрисдикцию или отсутствие логов.

Источники: [Статья 46 закона «О связи»](https://www.consultant.ru/document/cons_doc_LAW_43224/16bb16c212b64fca3cd16dac9f4f1f2c2fd34083/), [Internet Society: Russia’s National DNS](https://www.internetsociety.org/resources/internet-fragmentation/russias-national-dns/), [Mullvad: завершение публичного DNS](https://mullvad.net/en/blog/2026/9/3/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead).

## Защита совместимости

1. Не удалять и не переименовывать существующие ID/URL/категории; не менять `DNSCATVER`, `DNSCATREV` и `ENTRIES` при изменениях только LuCI.
2. Не добавлять непроверенные URL из стороннего справочника в доступный для автоназначения каталог.
3. Подсказки для ролей строить в LuCI по уже существующим тегам, не смешивать категорию и страну.
4. До выпуска прогнать GitHub Actions, затем проверить светлую/тёмную темы и назначение DNS на тестовом роутере.
