# Default Template Library: "Mono" Set

> Companion to `widget-app-brief.md`. Visual reference: `docs/reference/widgets-reference.jpg`.
> Build every template as a spec JSON in `WidgetKitCore/Resources/Templates/<id>.json` using only the layer types and bindings of spec v1.
> "Ref" points to where the matching tile sits in the reference image (rows top→bottom, columns left→right, approximate).

## Style tokens

| token | light | dark |
|---|---|---|
| `bg` | `#FFFFFF` | `#0E0E0E` |
| `fg` | `#0E0E0E` | `#FFFFFF` |
| `muted` | `#8A8A8A` | `#7A7A7A` |
| `accent` | `#E2231A` | `#E2231A` |
| `outer` (area around circle templates) | `#E6E9EC` | `#000000` |

- Numerals and short Latin labels: `dot` font (Doto). Small labels: `system`, size 9–11, uppercase, tracking +1.
- Arabic labels: `arabic` font, same sizes +1.
- Corner radius of inner cards/pills: 22 on small, 26 on medium.
- One accent color per widget at most. Users can change `accent` in the editor.

## Catalog

### Time
| id | name (en / ar) | family | Ref | Layout | Data |
|---|---|---|---|---|---|
| `mono.clock.analog` | Analog Clock / ساعة عقارب | small | R1 C7 | White circle face, 60 thin ticks (thicker every 5), black hour + minute hands, red center dot | `analogClock` classic, `refresh: minute` |
| `mono.clock.dotAnalog` | Dot Clock / ساعة نقط | small | R3 C3 | Black circle, white hands, 12 white dots instead of ticks, red dot marker at 6–7 o'clock | `analogClock` dot |
| `mono.clock.digital` | Dot Digital / ساعة رقمية | small | R4 C5 | Rounded white card, hour on top and minutes below in large `dot` numerals, thin divider between | `time.hh`, `time.mm` |
| `mono.date.big` | Big Date / التاريخ | small | R4 C8 | White rounded square, day number centered in `system-serif` ~64 | `date.d`, `refresh: daily` |
| `mono.date.dayZone` | Day & Zone / اليوم والتوقيت | small | R5 C4 | White card, weekday at top (`system`, uppercase), timezone offset large in `dot` at bottom | `date.EEEE`, `tz.offset`; field `timezone` turns it into a world clock showing that zone's time |

### Weather
| id | name | family | Ref | Layout | Data |
|---|---|---|---|---|---|
| `mono.weather.hiLo` | High / Low / العظمى والصغرى | small | R1 C1 | White circle, two lines: arrow-up + high, arrow-down + low in `dot` | `weather.hi`, `weather.lo` |
| `mono.weather.temp` | Temperature / الحرارة | small | R3 C1 | Red circle, white `dot` temperature, small condition icon | `weather.temp`, `weather.symbol` |
| `mono.weather.forecast` | Forecast / توقعات | medium | R4 C6–7 | Black card: icon + current temp + H/L top-left, city + condition top-right, 6-day row (day, icon, high, low) | `forecastRow`, field `city` |

### Health (only if HealthKit is verified in M0; otherwise bind to manual counter)
| id | name | family | Ref | Layout | Data |
|---|---|---|---|---|---|
| `mono.steps.streak` | Steps Streak / الخطوات | small | R1 C3 | White card: label "TOTAL STEPS", big `dot` number, divider, label "STREAK", value "N DAYS" | `steps.today`, `steps.streak` |
| `mono.steps.month` | Steps Month / شهر الخطوات | small | R5 C2 | Black card: big `dot` step total at top, `dotGrid` 5×7 of the month below (white = goal met, grey = missed, red = today) | `steps.monthGrid`, field `goal` |
| `mono.sleep.week` | Sleep Week / نوم الأسبوع | medium | R2 C4–5 | White card: 7 columns, each a vertical stack of small black dots (one per hour), red dot on the best night, day name + duration under each | `dotBars`, `sleep.week` |

### Focus & Countdown
| id | name | family | Ref | Layout | Data |
|---|---|---|---|---|---|
| `mono.focus.today` | Focus Today / تركيز اليوم | small | R1 C4 | Black card: red `dotBars` strip at top (last 7 days), big "6h 20" in `dot`, label "TOTAL TIME" | `focus.today`, `focus.week` (from the app's stopwatch) |
| `mono.countdown.red` | Countdown / العد التنازلي | small | R1 C8 | Red card: small label on top (e.g. "30m"), event title, big `dot` live countdown at bottom | field `title`, field `date` (`live.kind = timer`) |
| `mono.countdown.trip` | Trip Board / رحلة | medium | R6 C1–2 | Black card, `system-mono` uppercase lines: place, flight/event, route, "IN 19 MIN" live; bottom row: icon + origin, time range | fields `line1..3`, `date`, `start`, `end`. Default text generic: "CAIRO AIRPORT / FLIGHT XY 123 / CAI TO DXB" |
| `mono.stopwatch` | Stopwatch / ساعة إيقاف | small | R3 C2 + R3 C7 | Idle: red circle with "REC". Running: white circle with red dot + live elapsed `00:00:05`. Whole widget is a `button` | `stopwatch.toggle` intent, `stopwatch.start` with `live.kind = timer` |

### Prayer (not in the image; same style, high value for Egyptian users)
| id | name | family | Layout | Data |
|---|---|---|---|---|
| `mono.prayer.next` | Next Prayer / الصلاة القادمة | small | White card: prayer name (Arabic) on top, time in `dot`, live "in 1h 12m" in accent | `prayer.next.*` |
| `mono.prayer.day` | Prayer Times / مواقيت الصلاة | medium | Black card: 5 columns (Fajr…Isha) name + time, next prayer column highlighted red | `prayer.*` |
| `mono.qibla` | Qibla / القبلة | small | Black circle (Ref R5 C6 compass), "N" marker at top, dot arrow rotated to the Qibla bearing, degrees below | `qibla.bearing`, `location.*` |

### Counters
| id | name | family | Layout | Data |
|---|---|---|---|---|
| `mono.counter.tasbeeh` | Tasbeeh / سبحة | small | White card: current dhikr, next-dhikr button, big `dot` count in a ring, red round "+" button bottom-right, small reset button | `counter.dhikr`, `counter.value`, `counter.progress`, `counter.increment` (arg `{{field.target}}` for auto-advance), `counter.next`, `counter.reset`, field `target` (default 33) |

### Photo
| id | name | family | Ref | Layout |
|---|---|---|---|---|
| `mono.photo.square` | Photo / صورة | small | R4 C3 | User photo, `fill`, rounded mask |
| `mono.photo.circle` | Photo Circle / صورة دائرية | small | R2 C6 | User photo in a circle on `outer` background |
| `mono.photo.halftone` | Dot Portrait / صورة نقط | small | R6 C8 | User photo converted once to a black-on-white halftone (`filter: halftone`), optional small music-style badge |
| `mono.music.card` | Music Card / كارت موسيقى | small | R1 C5 | Black card: square cover image, title + artist below (no third-party logo); tap opens user's link | fields `cover`, `title`, `artist`, `url` (`open.url`) |

### Tiles (Shortcut launchers)
Replace all quick-setting tiles in the image (Torch, Wi-Fi, Bluetooth, Hotspot, Dark mode, Mic, Location, Airplane, NFC, Calculator, Home, TV remote, Bedtime, Screen recorder, Auto-rotate…).

| id | name | family | Ref | Layout |
|---|---|---|---|---|
| `mono.tiles.pills2` | 2 Tiles / زرارين | small | R2–R4 C1, C7 | 2 stacked capsules, each: icon in a circle + label; one tile can be red (active style) |
| `mono.tiles.pills4` | 4 Tiles / ٤ زراير | medium | same | 2×2 capsules |
| `mono.tiles.round` | Round Tiles / زراير دائرية | small | R2 C8–9 | 2×2 circular icon buttons, white and black alternating, one red |
| `mono.tiles.hero` | Big Tile / زرار كبير | small | R2 C6, R5 C7 | One circle filling the widget: icon + two-line label (e.g. "Auto Rotate") |

Each tile has fields: `icon` (from the SF Symbol whitelist), `label` (`{en,ar}`), `shortcut` (Shortcut name). Tap → `shortcut.run`. The editor shows a short guide on creating the Shortcut in the Shortcuts app.

## Live controls (ADR-027)

Fixed widgets, so they reach the home screen without an App Group.

| id | name | family | Layout |
|---|---|---|---|
| `mono.media.player` | Now Playing / يُشغَّل الآن | medium | Album art, song, artist, progress, times, previous, play/pause, next |
| `mono.control.center` | Control Center / مركز التحكم | large | Now playing with transport, six switches lit by their state, volume and brightness bars with up/down zones |
| `mono.timer.focus` | Timer / مؤقت | small | Ring and time left; tap to start or pause, +5, reset |

### Alive (ADR-028)

| id | name | family | Layout |
|---|---|---|---|
| `mono.year.dots` | Year Dots / نقاط السنة | small | Year label and percent, a dot grid lit by the real share of the year, days left |
| `mono.battery.mood` | Battery Mood / مزاج البطارية | small | A face from the `battery.mood` set, percent, a bolt while charging |
| `mono.weather.art` | Weather Art / رسمة الطقس | medium | A dot drawing from the `weather.art` set, city, temperature, condition, five days |
| `mono.tasks.small` | Next Task / المهمة التالية | small | Today's count, the next task with its checkbox, add |
| `mono.tasks.medium` | Tasks / المهام | medium | Header with count and add, four tasks with checkboxes |
| `mono.tasks.large` | Tasks Progress / تقدم المهام | large | Today's progress ring, six tasks with checkboxes, add |

## Skipped from the image (with reason)
- Nothing / brand logos and dot emblems (R4 C9, R5 C3, R6 C9): third-party branding.
- "Pair new device", Face ID / phone illustration, earbuds battery "CONNECT": system or other-device data iOS widgets can't read.
- Screen-time "over limit" tiles: rebound to countdown / focus templates above.
- Coordinates tile (R1 C6): add later as `mono.location.coords` if location in widget is verified.

## Acceptance
- 25 templates total (about 22 from the image style + 3 prayer/tasbeeh), each with light/dark where it makes sense.
- Every template validates, renders in the in-app preview and on the home screen, in Arabic and English.
- Snapshot test per template in `WidgetKitCore` tests (render to image, compare against a stored reference after first approval).
