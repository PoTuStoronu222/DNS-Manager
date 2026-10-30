# Аудит DoH-каталога — 30 октября 2026

Срез из одной сети: POST `example.com A`, проверка TLS, HTTP 200, типа `application/dns-message`, ID и признака DNS-ответа. Это проверка ответа, а не гарантия фильтрации, обхода, постоянной доступности или качества сервиса. Тайм-аут, ошибка TLS и иные сбои не доказывают закрытие сервиса.

Исходные 107 адресов: 81 ответ, 26 не подтверждены из этой сети. Дополнительные адреса из пользовательского списка проверены отдельно. Дата объявления Mullvad — рекомендация сменить настройки до 2 ноября, а не подтверждённое время отключения.

## Источники операторов

- [DNS-AI](https://dns-ai.ru/)
- [AstraCat](https://github.com/ASTRACAT2022/host-DNS)
- [Comss](https://www.comss.ru/page.php?id=7315)
- [Malw.link](https://info.dns.malw.link/)
- [Dagami](https://dns.dagami.ru/)
- [Bezmezhau](https://bezmezhau.com/)
- [GeoHide](https://geohide.ru/)
- [MagicDNS](https://magicdns.ru/)
- [Zapret DNS](https://dns.zapret.moe/)
- [Xbox DNS](https://family.xbox-dns.ru/)
- [Cloudflare](https://developers.cloudflare.com/1.1.1.1/setup/)
- [Google](https://developers.google.com/speed/public-dns/docs/doh)
- [Quad9](https://docs.quad9.net/services/)
- [AdGuard](https://adguard-dns.io/en/public-dns.html)
- [Control D](https://docs.controld.com/docs/free-dns)
- [DNS4EU](https://joindns4.eu/for-public)
- [CIRA](https://www.cira.ca/en/canadian-shield/configure/summary-cira-canadian-shield-dns-resolver-addresses/)
- [CleanBrowsing](https://cleanbrowsing.org/filters)
- [FFMUC](https://ffmuc.net/wiki/doku.php?id=knb:dohdot)
- [DNS.SB](https://dns.sb/doh/chrome/)
- [Applied Privacy](https://applied-privacy.net/services/dns/)
- [dnsforge](https://dnsforge.de/)
- [DNSGuard](https://dnsguard.pub/)
- [Surfshark](https://surfshark.com/dns)
- [Mullvad: announcement](https://mullvad.net/en/blog/2026/9/3/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead)

Ссылки относятся только к опубликованной операторами информации; прочерк в колонке источника означает, что адрес по первоисточнику не подтверждён в этом отчёте. Для GeoHide EU/US, wlrus и Geodema адреса предоставлены пользователем и проверены запросом; это не подтверждает заявленную географию или функции. GeoHide RU не ответил в этой сети.

## Результаты запросов

| ID | Название | DoH | Результат в одной сети | Источник оператора |
|---|---|---|---|---|
| mafioznik | Mafioznik DNS | https://dns.mafioznik.com/dns-query | не подтверждён (HTTP 000, код 6) | — |
| mafioznik_xyz | Mafioznik DNS XYZ | https://dns.mafioznik.xyz/dns-query | не подтверждён (HTTP 000, код 28) | — |
| astracat | AstraCat DNS | https://dns.commonnet.work/dns-query | DNS-ответ | [источник](https://github.com/ASTRACAT2022/host-DNS) |
| malw_link | Malw.link | https://dns.malw.link/dns-query | DNS-ответ | [источник](https://info.dns.malw.link/) |
| malw_cloudflare | Malw.link Cloudflare | https://5u35p8m9i7.cloudflare-gateway.com/dns-query | DNS-ответ | [источник](https://info.dns.malw.link/) |
| xbox_dns | Xbox DNS | https://xbox-dns.ru/dns-query | DNS-ответ | [источник](https://family.xbox-dns.ru/) |
| geohide | GeoHide DNS | https://dns.geohide.ru:444/dns-query | не подтверждён (HTTP 503, код 0) | — |
| geohide_8443 | GeoHide DNS :8443 | https://dns.geohide.ru:8443/dns-query | не подтверждён (HTTP 503, код 0) | — |
| geohide_eu | GeoHide EU | https://eu.geohide.ru/dns-query | DNS-ответ | — |
| geohide_us | GeoHide US | https://us.geohide.ru/dns-query | DNS-ответ | — |
| comss_ru | Comss DNS RU | https://dns.comss.ru/dns-query | не подтверждён (HTTP 000, код 6) | — |
| comss_bypass | Comss.one | https://dns.comss.one/dns-query | DNS-ответ | [источник](https://www.comss.ru/page.php?id=7315) |
| comss_adblock_bypass | Comss.one Router | https://router.comss.one/dns-query | DNS-ответ | — |
| dns_ai_ru | DNS-AI.RU | https://dns.dns-ai.ru/dns-query | DNS-ответ | [источник](https://dns-ai.ru/) |
| magicdns | MagicDNS | https://dns.magicdns.ru/dns-query | DNS-ответ | [источник](https://magicdns.ru/) |
| wlrus | wlrus DNS | https://dns.wlrus.cfd/dns-query | DNS-ответ | — |
| geodema | Geodema DNS | https://dns.geodema.love/dns-query | DNS-ответ | — |
| bezmezhau | Bezmezhau DNS | https://dns.bezmezhau.com/dns-query | не подтверждён (HTTP 000, код 28) | [источник](https://bezmezhau.com/) |
| dagami | Dagami DNS | https://dns.dagami.ru/dns-query | DNS-ответ | [источник](https://dns.dagami.ru/) |
| webshift | WebShift DNS | https://d.webshiftvpn.ru/dns-query | DNS-ответ | — |
| libredns_clean | LibreDNS | https://doh.libredns.gr/dns-query | DNS-ответ | — |
| yo1nk | YO1NK DNS | https://dns.yo1nk.app/dns-query | не подтверждён (HTTP 000, код 6) | — |
| dynx | DynX DNS | https://dns.dynx.pro/dns-query | не подтверждён (HTTP 000, код 7) | — |
| paesa | Paesa DNS | https://dns.paesa.es/dns-query | DNS-ответ | — |
| anon_no | Anon.no DNS | https://dns.anon.no/dns-query | DNS-ответ | — |
| bebas_unfiltered | BebasDNS Unfiltered | https://dns.bebasid.com/unfiltered | не подтверждён (HTTP 200, код 0) | — |
| dns4all | DNS4all | https://doh.dns4all.eu/dns-query | DNS-ответ | — |
| dns4eu_unfiltered | DNS4EU Unfiltered | https://unfiltered.joindns4.eu/dns-query | DNS-ответ | [источник](https://joindns4.eu/for-public) |
| shecan | Zapret DNS | https://dns.zapret.moe/dns-query | DNS-ответ | [источник](https://dns.zapret.moe/) |
| yandex_ru | Yandex RU | https://common.dot.dns.yandex.net/dns-query | DNS-ответ | — |
| yandex_safe | Yandex Safe | https://safe.dot.dns.yandex.net/dns-query | DNS-ответ | — |
| yandex_family | Yandex Family | https://family.dot.dns.yandex.net/dns-query | DNS-ответ | — |
| cloudflare_clean | Cloudflare | https://cloudflare-dns.com/dns-query | DNS-ответ | [источник](https://developers.cloudflare.com/1.1.1.1/setup/) |
| google_clean | Google Public DNS | https://dns.google/dns-query | DNS-ответ | [источник](https://developers.google.com/speed/public-dns/docs/doh) |
| quad9_unfiltered | Quad9 Unsecured | https://dns10.quad9.net/dns-query | DNS-ответ | [источник](https://docs.quad9.net/services/) |
| adguard_unfiltered | AdGuard Unfiltered | https://unfiltered.adguard-dns.com/dns-query | не подтверждён (HTTP 000, код 28) | [источник](https://adguard-dns.io/en/public-dns.html) |
| controld_p0 | Control D Unfiltered | https://freedns.controld.com/p0 | DNS-ответ | [источник](https://docs.controld.com/docs/free-dns) |
| controld_uncensored | Control D Uncensored | https://freedns.controld.com/uncensored | DNS-ответ | [источник](https://docs.controld.com/docs/free-dns) |
| he_public | Hurricane Electric Public Recursor | https://ordns.he.net/dns-query | DNS-ответ | — |
| 18bit_cn | 18bit.cn | https://doh.18bit.cn/dns-query | не подтверждён (HTTP 000, код 28) | — |
| aa_dns | Andrews & Arnold | https://dns.aa.net.uk/dns-query | DNS-ответ | — |
| aquilenet | Aquilenet DNS | https://dns.aquilenet.fr/dns-query | DNS-ответ | — |
| belnet | Belnet DNS | https://dns.belnet.be/dns-query | DNS-ответ | — |
| cynthia | CynthiaLabs DNS | https://dns.cynthialabs.net/dns-query | не подтверждён (HTTP 403, код 0) | — |
| digitalsize | DigitalSize DNS | https://dns.digitalsize.net/dns-query | DNS-ответ | — |
| dnshome | DNSHome | https://dns.dnshome.de/dns-query | не подтверждён (HTTP 000, код 28) | — |
| one_dns_pure | OneDNS Pure | https://doh-pure.onedns.net/dns-query | не подтверждён (HTTP 000, код 28) | — |
| dns_pub | DNSPod Public DNS | https://dns.pub/dns-query | не подтверждён (HTTP 000, код 35) | — |
| dns_fdn0 | FDN DNS 0 | https://ns0.fdn.fr/dns-query | DNS-ответ | — |
| dns_fdn1 | FDN DNS 1 | https://ns1.fdn.fr/dns-query | DNS-ответ | — |
| doh_lacontrevoie | LaContreVoie DNS | https://doh.lacontrevoie.fr/dns-query | DNS-ответ | — |
| cznic_odvr_doh | CZ.NIC ODVR DNS-сервер | https://odvr.nic.cz/doh | DNS-ответ | — |
| cznic_odvr_query | CZ.NIC ODVR Query | https://odvr.nic.cz/dns-query | DNS-ответ | — |
| doh_seby | Seby DNS | https://doh.seby.io/dns-query | не подтверждён (HTTP 000, код 28) | — |
| dns_surfshark | Surfshark DNS | https://dns.surfsharkdns.com/dns-query | не подтверждён (HTTP 000, код 60) | [источник](https://surfshark.com/dns) |
| hostux | Hostux DNS | https://dns.hostux.net/dns-query | DNS-ответ | — |
| cloudflare_security | Cloudflare Security | https://security.cloudflare-dns.com/dns-query | DNS-ответ | [источник](https://developers.cloudflare.com/1.1.1.1/setup/) |
| quad9_secure | Quad9 Secure | https://dns.quad9.net/dns-query | DNS-ответ | [источник](https://docs.quad9.net/services/) |
| quad9_ecs | Quad9 Secure ECS | https://dns11.quad9.net/dns-query | DNS-ответ | [источник](https://docs.quad9.net/services/) |
| controld_p1 | Control D Malware | https://freedns.controld.com/p1 | DNS-ответ | [источник](https://docs.controld.com/docs/free-dns) |
| opendns_standard | OpenDNS Standard | https://doh.opendns.com/dns-query | DNS-ответ | — |
| cleanbrowsing_security | CleanBrowsing Security | https://doh.cleanbrowsing.org/doh/security-filter/ | DNS-ответ | [источник](https://cleanbrowsing.org/filters) |
| dns4eu_protective | DNS4EU Protective | https://protective.joindns4.eu/dns-query | DNS-ответ | [источник](https://joindns4.eu/for-public) |
| cert_ee | CERT-EE | https://dns.cert.ee/dns-query | DNS-ответ | — |
| cira_protected | CIRA Protected | https://protected.canadianshield.cira.ca/dns-query | DNS-ответ | [источник](https://www.cira.ca/en/canadian-shield/configure/summary-cira-canadian-shield-dns-resolver-addresses/) |
| one_dns_block | OneDNS Block | https://doh.onedns.net/dns-query | не подтверждён (HTTP 000, код 35) | — |
| hagezi_root | HaGeZi Root | https://root.hagezi.org/dns-query | не подтверждён (HTTP 000, код 28) | — |
| hagezi_wurzn | HaGeZi Wurzn | https://wurzn.hagezi.org/dns-query | не подтверждён (HTTP 000, код 28) | — |
| hagezi_juuri | HaGeZi Juuri | https://juuri.hagezi.org/dns-query | не подтверждён (HTTP 000, код 28) | — |
| hagezi_ctif | HaGeZi CTIF | https://ctif.hagezi.org/dns-query | не подтверждён (HTTP 000, код 28) | — |
| openbld_ada | OpenBLD ADA | https://ada.openbld.net/dns-query | DNS-ответ | — |
| openbld_ric | OpenBLD RIC | https://ric.openbld.net/dns-query | DNS-ответ | — |
| dnsforge_strict | dnsforge Strict | https://hard.dnsforge.de/dns-query | DNS-ответ | — |
| dnsbunker | DNSBUNKER Pro+TIF | https://dnsbunker.org/dns-query | DNS-ответ | — |
| nsec_arnor | arnor.org | https://nsec.arnor.org/dns-query | не подтверждён (HTTP 000, код 28) | — |
| nextdns_fast | NextDNS | https://dns.nextdns.io | DNS-ответ | — |
| nextdns_anycast | NextDNS Anycast | https://anycast.dns.nextdns.io | DNS-ответ | — |
| dns_sb | DNS.SB | https://doh.dns.sb/dns-query | DNS-ответ | [источник](https://dns.sb/doh/chrome/) |
| cubedns | CubeDNS | https://cubedns.com/dns-query | не подтверждён (HTTP 000, код 28) | — |
| applied_privacy | Applied Privacy | https://doh.applied-privacy.net/query | DNS-ответ | [источник](https://applied-privacy.net/services/dns/) |
| cznic_odvr | CZ.NIC ODVR | https://odvr.nic.cz/doh | DNS-ответ | — |
| digitale_gesellschaft | Digitale Gesellschaft | https://dns.digitale-gesellschaft.ch/dns-query | DNS-ответ | — |
| cira_private | CIRA Private | https://private.canadianshield.cira.ca/dns-query | DNS-ответ | [источник](https://www.cira.ca/en/canadian-shield/configure/summary-cira-canadian-shield-dns-resolver-addresses/) |
| switch_ch | SWITCH DNS | https://dns.switch.ch/dns-query | DNS-ответ | — |
| wikimedia | Wikimedia DNS | https://wikimedia-dns.org/dns-query | DNS-ответ | — |
| pumplex | PumpleX | https://dns.pumplex.com/dns-query | не подтверждён (HTTP 000, код 28) | — |
| dnsforge | dnsforge | https://dnsforge.de/dns-query | DNS-ответ | — |
| ffmuc | FFMUC | https://doh.ffmuc.net/dns-query | DNS-ответ | [источник](https://ffmuc.net/wiki/doku.php?id=knb:dohdot) |
| adguard_default | AdGuard DNS | https://dns.adguard-dns.com/dns-query | DNS-ответ | [источник](https://adguard-dns.io/en/public-dns.html) |
| controld_p2 | Control D Ads+Tracking | https://freedns.controld.com/p2 | DNS-ответ | [источник](https://docs.controld.com/docs/free-dns) |
| dns4eu_noads | DNS4EU No Ads | https://noads.joindns4.eu/dns-query | DNS-ответ | [источник](https://joindns4.eu/for-public) |
| libredns_ads | LibreDNS Ads | https://doh.libredns.gr/ads | DNS-ответ | — |
| dnsguard | DNSGuard | https://dns.dnsguard.pub/dns-query | DNS-ответ | [источник](https://dnsguard.pub/) |
| nwps_standard | NWPS.fi Standard | https://public.ns.nwps.fi/dns-query | DNS-ответ | — |
| oszx | OSZX DNS | https://dns.oszx.co/dns-query | не подтверждён (HTTP 000, код 6) | — |
| angry_im | Angry.im | https://doh.angry.im/dns-query | DNS-ответ | — |
| dns_bebas_default | BebasDNS | https://dns.bebasid.com/dns-query | DNS-ответ | — |
| blokada | Blokada DNS | https://dns.blokada.org/dns-query | DNS-ответ | — |
| cloudflare_family | Cloudflare Family | https://family.cloudflare-dns.com/dns-query | DNS-ответ | [источник](https://developers.cloudflare.com/1.1.1.1/setup/) |
| adguard_family | AdGuard Family | https://family.adguard-dns.com/dns-query | DNS-ответ | [источник](https://adguard-dns.io/en/public-dns.html) |
| mullvad_family | Mullvad Family (сменить до 02.11.2026) | https://family.dns.mullvad.net/dns-query | DNS-ответ | [источник](https://mullvad.net/en/blog/2026/9/3/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead) |
| mullvad_all | Mullvad All (сменить до 02.11.2026) | https://all.dns.mullvad.net/dns-query | DNS-ответ | [источник](https://mullvad.net/en/blog/2026/9/3/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead) |
| controld_family | Control D Family | https://freedns.controld.com/family | DNS-ответ | [источник](https://docs.controld.com/docs/free-dns) |
| opendns_family | OpenDNS FamilyShield | https://doh.familyshield.opendns.com/dns-query | DNS-ответ | — |
| cleanbrowsing_adult | CleanBrowsing Adult | https://doh.cleanbrowsing.org/doh/adult-filter/ | DNS-ответ | [источник](https://cleanbrowsing.org/filters) |
| cleanbrowsing_family | CleanBrowsing Family | https://doh.cleanbrowsing.org/doh/family-filter/ | DNS-ответ | [источник](https://cleanbrowsing.org/filters) |
| dns4eu_child | DNS4EU Child | https://child.joindns4.eu/dns-query | DNS-ответ | [источник](https://joindns4.eu/for-public) |
| dns4eu_child_noads | DNS4EU Child No Ads | https://child-noads.joindns4.eu/dns-query | DNS-ответ | [источник](https://joindns4.eu/for-public) |
| dns_for_family | DNS for Family | https://dns-doh.dnsforfamily.com/dns-query | DNS-ответ | — |
| cira_family | CIRA Family | https://family.canadianshield.cira.ca/dns-query | DNS-ответ | [источник](https://www.cira.ca/en/canadian-shield/configure/summary-cira-canadian-shield-dns-resolver-addresses/) |
| nwps_kids | NWPS.fi Kids | https://kids.ns.nwps.fi/dns-query | DNS-ответ | — |
| iijjp | IIJ.JP DNS | https://public.dns.iij.jp/dns-query | DNS-ответ | — |
| dnsforge_youth | dnsforge Youth Protection | https://clean.dnsforge.de/dns-query | DNS-ответ | — |

## Не добавлены без подтверждения DoH

`dns.nullproxy.com`, `dns2.mafioznik.xyz`, `dot.dns.astracat.ru`, `free.shecan.ir`, `pro.shecan.ir`: входные данные содержат имена DoT или зеркал, но доступность предложенного DoH из этой сети и актуальный официальный DoH URL не подтверждены. `dns.astracat.ru` указан во входных данных, однако текущий репозиторий оператора публикует `dns.commonnet.work`. Существующие записи и ID не удалялись.
## Повторная проверка и категории

При повторном запросе все 113 записей проверены из той же сети: 90 дали DNS-ответ, 23 не подтвердились. Из первоначально не подтвердившихся ответили `doh_seby`, `geohide` и `geohide_8443`. Результаты в таблице выше относятся к первому запуску; вторая попытка показывает, что единичный сбой не доказывает закрытие сервиса.

- [CZ.NIC](https://blog.nic.cz/2019/05/20/na-odvr-podporujeme-take-dns-over-https/) описывает ODVR как нефильтрующий DNS, поэтому `cznic_odvr` перенесён из категории защиты от угроз в обычные DNS. `cznic_odvr_doh` сохраняет тот же URL и ID для совместимости и помечен как дубликат. Автоматический выбор уже исключает одинаковые URL.
- [IIJ](https://policy.public.dns.iij.jp/) указывает, что публичный DNS не фильтрует вредоносные сайты и не является общим семейным фильтром. `iijjp` перенесён из семейной категории в конфиденциальность, без изменения ID и адреса.
- [18Bit](https://www.18bit.cn/help-docs/help-docs-windows.html) публикует существующий URL как фильтр рекламы. Исправлены название и неверный тег `unfiltered`; категория блокировки рекламы сохранена.
- [Switch](https://portal.switch.ch/pub/public-dns/) подтверждает фильтрацию угроз, поэтому его категория безопасности сохранена.
- [HaGeZi](https://github.com/hagezi/dns-servers/blob/main/README.md) подтверждает все четыре адреса, названия и фильтрацию. Из нашей сети повторно ответа не было; оператор указывает, что причиной может быть сетевая блокировка. Это не основание считать серверы закрытыми.
- [DNSHome](https://www.dnshome.de/doh-dot-public-resolver.php) и [Surfshark](https://surfshark.com/dns) публикуют те же адреса, которые уже есть в каталоге, хотя из проверочной сети ответа не было; Surfshark вернул ошибку проверки сертификата. Отключать проверку TLS для обхода ошибки нельзя.

Изменение каталога не переназначает выбранные DNS. При следующем выборе профиля старые результаты с прежним хешем каталога не считаются свежими и проверяются заново. Для уже выбранного профиля его назначение сохраняется до действий пользователя или штатной автозамены.
