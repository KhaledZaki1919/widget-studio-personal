# Capabilities

Generated from `capabilities.json` by `scripts/capabilities-table.mjs`. Do not edit by hand.

## Time and date

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{time.hh}}` | Hour | Yes | Yes |  |  |  |
| `{{time.h}}` | Hour (12h, no zero) | Yes | Yes |  |  |  |
| `{{time.mm}}` | Minutes | Yes | Yes |  |  |  |
| `{{time.ampm}}` | AM/PM | Yes | Yes |  |  |  |
| `{{date.d}}` | Day of month | Yes | Yes |  |  |  |
| `{{date.dd}}` | Day, two digits | Yes | Yes |  |  |  |
| `{{date.EEEE}}` | Weekday | Yes | Yes |  |  |  |
| `{{date.EEE}}` | Weekday, short | Yes | Yes |  |  |  |
| `{{date.MMM}}` | Month, short | Yes | Yes |  |  |  |
| `{{date.MMMM}}` | Month | Yes | Yes |  |  |  |
| `{{date.M}}` | Month number | Yes | Yes |  |  |  |
| `{{date.yyyy}}` | Year | Yes | Yes |  |  |  |
| `{{date.hijri}}` | Hijri date | Yes | Yes |  |  |  |
| `{{tz.offset}}` | Time zone offset | Yes | Yes |  |  |  |
| `{{tz.<timezoneField>.time}}` | Time in a city | Yes | Yes |  |  |  |
| `{{days.<dateField>}}` | Days left | Yes | Yes |  |  |  |
| `{{year.progress}}` | Year progress | Yes | Yes |  |  |  |
| `{{month.progress}}` | Month progress | Yes | Yes |  |  |  |
| `{{week.progress}}` | Week progress | Yes | Yes |  |  |  |
| `{{day.progress}}` | Day progress | Yes | Yes |  |  |  |
| `{{year.day}}` | Day of the year | Yes | Yes |  |  |  |
| `{{year.daysLeft}}` | Days left in the year | Yes | Yes |  |  |  |
| `{{month.daysLeft}}` | Days left in the month | Yes | Yes |  |  |  |
| `{{week.daysLeft}}` | Days left in the week | Yes | Yes |  |  |  |
| `{{time.isDay}}` | Daytime | Yes | Yes |  |  |  |
| `{{time.ss}}` | Seconds | No | Yes |  |  | iOS: A widget redraws at most once a minute, so seconds stand still between redraws. |
| `{{time.words}}` | Time in words | Yes | Yes |  |  |  |
| `{{date.EE}}` | Weekday, two letters | Yes | Yes |  |  |  |
| `{{week.d1.EEE}}` | Week day 1, name | Yes | Yes |  |  |  |
| `{{week.d1.d}}` | Week day 1, date | Yes | Yes |  |  |  |
| `{{week.d1.isToday}}` | Week day 1 is today | Yes | Yes |  |  |  |
| `{{week.d2.EEE}}` | Week day 2, name | Yes | Yes |  |  |  |
| `{{week.d2.d}}` | Week day 2, date | Yes | Yes |  |  |  |
| `{{week.d2.isToday}}` | Week day 2 is today | Yes | Yes |  |  |  |
| `{{week.d3.EEE}}` | Week day 3, name | Yes | Yes |  |  |  |
| `{{week.d3.d}}` | Week day 3, date | Yes | Yes |  |  |  |
| `{{week.d3.isToday}}` | Week day 3 is today | Yes | Yes |  |  |  |
| `{{week.d4.EEE}}` | Week day 4, name | Yes | Yes |  |  |  |
| `{{week.d4.d}}` | Week day 4, date | Yes | Yes |  |  |  |
| `{{week.d4.isToday}}` | Week day 4 is today | Yes | Yes |  |  |  |
| `{{week.d5.EEE}}` | Week day 5, name | Yes | Yes |  |  |  |
| `{{week.d5.d}}` | Week day 5, date | Yes | Yes |  |  |  |
| `{{week.d5.isToday}}` | Week day 5 is today | Yes | Yes |  |  |  |
| `{{week.d6.EEE}}` | Week day 6, name | Yes | Yes |  |  |  |
| `{{week.d6.d}}` | Week day 6, date | Yes | Yes |  |  |  |
| `{{week.d6.isToday}}` | Week day 6 is today | Yes | Yes |  |  |  |
| `{{week.d7.EEE}}` | Week day 7, name | Yes | Yes |  |  |  |
| `{{week.d7.d}}` | Week day 7, date | Yes | Yes |  |  |  |
| `{{week.d7.isToday}}` | Week day 7 is today | Yes | Yes |  |  |  |

## Weather

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{weather.temp}}` | Temperature | Yes | Yes |  |  |  |
| `{{weather.hi}}` | Today's high | Yes | Yes |  |  |  |
| `{{weather.lo}}` | Today's low | Yes | Yes |  |  |  |
| `{{weather.feels}}` | Feels like | Yes | Yes |  |  |  |
| `{{weather.humidity}}` | Humidity | Yes | Yes |  |  |  |
| `{{weather.wind}}` | Wind | Yes | Yes |  |  |  |
| `{{weather.sunrise}}` | Sunrise | Yes | Yes |  |  |  |
| `{{weather.sunset}}` | Sunset | Yes | Yes |  |  |  |
| `{{weather.cond}}` | Condition | Yes | Yes |  |  |  |
| `{{weather.symbol}}` | Condition icon | Yes | Yes |  |  |  |
| `{{weather.city}}` | City | Yes | Yes |  |  |  |
| `{{weather.kind}}` | Condition kind | Yes | Yes |  |  |  |
| `{{forecast.1.day}}` | Forecast day 1 | Yes | Yes |  |  |  |
| `{{forecast.1.symbol}}` | Forecast icon 1 | Yes | Yes |  |  |  |
| `{{forecast.1.hi}}` | Forecast high 1 | Yes | Yes |  |  |  |
| `{{forecast.1.lo}}` | Forecast low 1 | Yes | Yes |  |  |  |
| `{{forecast.2.day}}` | Forecast day 2 | Yes | Yes |  |  |  |
| `{{forecast.2.symbol}}` | Forecast icon 2 | Yes | Yes |  |  |  |
| `{{forecast.2.hi}}` | Forecast high 2 | Yes | Yes |  |  |  |
| `{{forecast.2.lo}}` | Forecast low 2 | Yes | Yes |  |  |  |
| `{{forecast.3.day}}` | Forecast day 3 | Yes | Yes |  |  |  |
| `{{forecast.3.symbol}}` | Forecast icon 3 | Yes | Yes |  |  |  |
| `{{forecast.3.hi}}` | Forecast high 3 | Yes | Yes |  |  |  |
| `{{forecast.3.lo}}` | Forecast low 3 | Yes | Yes |  |  |  |
| `{{forecast.4.day}}` | Forecast day 4 | Yes | Yes |  |  |  |
| `{{forecast.4.symbol}}` | Forecast icon 4 | Yes | Yes |  |  |  |
| `{{forecast.4.hi}}` | Forecast high 4 | Yes | Yes |  |  |  |
| `{{forecast.4.lo}}` | Forecast low 4 | Yes | Yes |  |  |  |
| `{{forecast.5.day}}` | Forecast day 5 | Yes | Yes |  |  |  |
| `{{forecast.5.symbol}}` | Forecast icon 5 | Yes | Yes |  |  |  |
| `{{forecast.5.hi}}` | Forecast high 5 | Yes | Yes |  |  |  |
| `{{forecast.5.lo}}` | Forecast low 5 | Yes | Yes |  |  |  |
| `{{forecast.6.day}}` | Forecast day 6 | Yes | Yes |  |  |  |
| `{{forecast.6.symbol}}` | Forecast icon 6 | Yes | Yes |  |  |  |
| `{{forecast.6.hi}}` | Forecast high 6 | Yes | Yes |  |  |  |
| `{{forecast.6.lo}}` | Forecast low 6 | Yes | Yes |  |  |  |
| `{{hourly.1.time}}` | Hour 1 | Yes | Yes |  |  |  |
| `{{hourly.1.symbol}}` | Hour 1 icon | Yes | Yes |  |  |  |
| `{{hourly.1.temp}}` | Hour 1 temperature | Yes | Yes |  |  |  |
| `{{hourly.2.time}}` | Hour 2 | Yes | Yes |  |  |  |
| `{{hourly.2.symbol}}` | Hour 2 icon | Yes | Yes |  |  |  |
| `{{hourly.2.temp}}` | Hour 2 temperature | Yes | Yes |  |  |  |
| `{{hourly.3.time}}` | Hour 3 | Yes | Yes |  |  |  |
| `{{hourly.3.symbol}}` | Hour 3 icon | Yes | Yes |  |  |  |
| `{{hourly.3.temp}}` | Hour 3 temperature | Yes | Yes |  |  |  |
| `{{hourly.4.time}}` | Hour 4 | Yes | Yes |  |  |  |
| `{{hourly.4.symbol}}` | Hour 4 icon | Yes | Yes |  |  |  |
| `{{hourly.4.temp}}` | Hour 4 temperature | Yes | Yes |  |  |  |
| `{{hourly.5.time}}` | Hour 5 | Yes | Yes |  |  |  |
| `{{hourly.5.symbol}}` | Hour 5 icon | Yes | Yes |  |  |  |
| `{{hourly.5.temp}}` | Hour 5 temperature | Yes | Yes |  |  |  |
| `{{hourly.6.time}}` | Hour 6 | Yes | Yes |  |  |  |
| `{{hourly.6.symbol}}` | Hour 6 icon | Yes | Yes |  |  |  |
| `{{hourly.6.temp}}` | Hour 6 temperature | Yes | Yes |  |  |  |
| `{{hourly.7.time}}` | Hour 7 | Yes | Yes |  |  |  |
| `{{hourly.7.symbol}}` | Hour 7 icon | Yes | Yes |  |  |  |
| `{{hourly.7.temp}}` | Hour 7 temperature | Yes | Yes |  |  |  |
| `{{hourly.8.time}}` | Hour 8 | Yes | Yes |  |  |  |
| `{{hourly.8.symbol}}` | Hour 8 icon | Yes | Yes |  |  |  |
| `{{hourly.8.temp}}` | Hour 8 temperature | Yes | Yes |  |  |  |
| `{{hourly.temps}}` | Next 24 hours | Yes | Yes |  |  |  |
| `{{weather.rainChance}}` | Chance of rain | Yes | Yes |  |  |  |
| `{{weather.rainNext}}` | Rain soon | Yes | Yes |  |  |  |
| `{{weather.uv}}` | UV index | Yes | Yes |  |  |  |
| `{{weather.aqi}}` | Air quality | Yes | Yes |  |  |  |

## Battery

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{battery.level}}` | Battery level | Yes | Yes |  |  |  |
| `{{battery.charging}}` | Charging | Yes | Yes |  |  |  |
| `{{battery.symbol}}` | Battery icon | Yes | Yes |  |  |  |
| `{{battery.devices}}` | Earbuds and watch battery | No | No |  |  | iOS: No public API. Android: Needs a privileged permission. |

## Location

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{location.lat}}` | Latitude | Yes | Yes | Location | Location |  |
| `{{location.lon}}` | Longitude | Yes | Yes | Location | Location |  |
| `{{location.alt}}` | Altitude | Yes | Yes | Location | Location |  |
| `{{location.city}}` | Current place | Yes | Yes | Location | Location |  |

## Prayer and Qibla

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{prayer.next.name}}` | Next prayer | Yes | Yes | Location | Location |  |
| `{{prayer.next.time}}` | Next prayer time | Yes | Yes | Location | Location |  |
| `{{prayer.next.key}}` | Next prayer key | Yes | Yes | Location | Location |  |
| `{{prayer.fajr}}` | Fajr | Yes | Yes | Location | Location |  |
| `{{prayer.dhuhr}}` | Dhuhr | Yes | Yes | Location | Location |  |
| `{{prayer.asr}}` | Asr | Yes | Yes | Location | Location |  |
| `{{prayer.maghrib}}` | Maghrib | Yes | Yes | Location | Location |  |
| `{{prayer.isha}}` | Isha | Yes | Yes | Location | Location |  |
| `{{qibla.bearing}}` | Qibla direction | Yes | Yes | Location | Location |  |

## Steps and sleep

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{steps.today}}` | Steps today | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{steps.progress}}` | Step goal progress | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{steps.streak}}` | Step streak | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{steps.month}}` | Steps this month | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{steps.monthGrid}}` | Steps month grid | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{sleep.lastNight}}` | Sleep last night | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{sleep.bedtime}}` | Bedtime | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{sleep.wake}}` | Wake time | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{sleep.week}}` | Sleep this week | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{heart.rate}}` | Heart rate | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{heart.resting}}` | Resting heart rate | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{heart.today}}` | Heart rate today | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{stress.level}}` | Stress | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{energy.level}}` | Energy | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{activity.minutes}}` | Active minutes | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{activity.kcal}}` | Active calories | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{sleep.time}}` | Sleep, h:mm | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{sleep.stages}}` | Sleep stages | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |
| `{{steps.hourly}}` | Steps per hour | Yes | Yes | Health (steps and sleep) | Health (steps and sleep) |  |

## Counters and timers

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{counter.value}}` | Counter | Yes | Yes |  |  |  |
| `{{counter.progress}}` | Counter progress | Yes | Yes |  |  |  |
| `{{counter.dhikr}}` | Current dhikr | Yes | Yes |  |  |  |
| `{{stopwatch.running}}` | Stopwatch running | Yes | Yes |  |  |  |
| `{{stopwatch.start}}` | Stopwatch start | Yes | Yes |  |  |  |
| `{{focus.today}}` | Focus today | Yes | Yes |  |  |  |
| `{{focus.week}}` | Focus this week | Yes | Yes |  |  |  |
| `{{timer.running}}` | Timer running | Yes | Yes |  |  |  |
| `{{timer.end}}` | Timer end | Yes | Yes |  |  |  |
| `{{timer.remaining}}` | Timer left | Yes | Yes |  |  |  |
| `{{timer.progress}}` | Timer progress | Yes | Yes |  |  |  |
| `counter.increment` | Counter +1 | Yes | Yes |  |  |  |
| `counter.reset` | Reset counter | Yes | Yes |  |  |  |
| `counter.next` | Next dhikr | Yes | Yes |  |  |  |
| `stopwatch.toggle` | Start/stop stopwatch | Yes | Yes |  |  |  |
| `timer.toggle` | Start/pause timer | Yes | Yes |  |  |  |
| `timer.add` | Add time to timer | Yes | Yes |  |  |  |
| `timer.reset` | Reset timer | Yes | Yes |  |  |  |

## Calendar

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{calendar.next.title}}` | Next event | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.next.time}}` | Next event time | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.next.location}}` | Next event place | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.count}}` | Events today | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.1.title}}` | Event 1 | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.1.time}}` | Event 1 time | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.2.title}}` | Event 2 | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.2.time}}` | Event 2 time | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.3.title}}` | Event 3 | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.3.time}}` | Event 3 time | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.4.title}}` | Event 4 | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.4.time}}` | Event 4 time | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.1.end}}` | Event 1 end | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.1.calendar}}` | Event 1 calendar | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.1.color}}` | Event 1 color | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.2.end}}` | Event 2 end | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.2.calendar}}` | Event 2 calendar | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.2.color}}` | Event 2 color | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.3.end}}` | Event 3 end | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.3.calendar}}` | Event 3 calendar | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.3.color}}` | Event 3 color | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.4.end}}` | Event 4 end | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.4.calendar}}` | Event 4 calendar | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.4.color}}` | Event 4 color | Yes | Yes | Calendar | Calendar |  |
| `{{calendar.next.end}}` | Next event end | Yes | Yes | Calendar | Calendar |  |

## Reminders

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{reminders.count}}` | Open reminders | Yes | No | Reminders | Reminders | Android: Android has no shared reminders store. |
| `{{reminders.1.title}}` | Reminder 1 | Yes | No | Reminders | Reminders |  |
| `{{reminders.2.title}}` | Reminder 2 | Yes | No | Reminders | Reminders |  |
| `{{reminders.3.title}}` | Reminder 3 | Yes | No | Reminders | Reminders |  |
| `{{reminders.4.title}}` | Reminder 4 | Yes | No | Reminders | Reminders |  |

## Tasks

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{tasks.list}}` | Open tasks | Yes | Yes | Reminders |  |  |
| `{{tasks.today.count}}` | Tasks today | Yes | Yes | Reminders |  |  |
| `{{tasks.open.count}}` | Open task count | Yes | Yes | Reminders |  |  |
| `{{tasks.done.count}}` | Tasks done today | Yes | Yes | Reminders |  |  |
| `{{tasks.progress}}` | Task progress | Yes | Yes | Reminders |  |  |
| `{{tasks.next.title}}` | Next task | Yes | Yes | Reminders |  |  |
| `{{tasks.next.due}}` | Next task due | Yes | Yes | Reminders |  |  |
| `{{tasks.next.id}}` | Next task id | Yes | Yes | Reminders |  |  |
| `{{tasks.1.title}}` | Task 1 | Yes | Yes | Reminders |  |  |
| `{{tasks.1.due}}` | Task 1 due | Yes | Yes | Reminders |  |  |
| `{{tasks.1.done}}` | Task 1 done | Yes | Yes | Reminders |  |  |
| `{{tasks.1.id}}` | Task 1 id | Yes | Yes | Reminders |  |  |
| `{{tasks.2.title}}` | Task 2 | Yes | Yes | Reminders |  |  |
| `{{tasks.2.due}}` | Task 2 due | Yes | Yes | Reminders |  |  |
| `{{tasks.2.done}}` | Task 2 done | Yes | Yes | Reminders |  |  |
| `{{tasks.2.id}}` | Task 2 id | Yes | Yes | Reminders |  |  |
| `{{tasks.3.title}}` | Task 3 | Yes | Yes | Reminders |  |  |
| `{{tasks.3.due}}` | Task 3 due | Yes | Yes | Reminders |  |  |
| `{{tasks.3.done}}` | Task 3 done | Yes | Yes | Reminders |  |  |
| `{{tasks.3.id}}` | Task 3 id | Yes | Yes | Reminders |  |  |
| `{{tasks.4.title}}` | Task 4 | Yes | Yes | Reminders |  |  |
| `{{tasks.4.due}}` | Task 4 due | Yes | Yes | Reminders |  |  |
| `{{tasks.4.done}}` | Task 4 done | Yes | Yes | Reminders |  |  |
| `{{tasks.4.id}}` | Task 4 id | Yes | Yes | Reminders |  |  |
| `{{tasks.5.title}}` | Task 5 | Yes | Yes | Reminders |  |  |
| `{{tasks.5.due}}` | Task 5 due | Yes | Yes | Reminders |  |  |
| `{{tasks.5.done}}` | Task 5 done | Yes | Yes | Reminders |  |  |
| `{{tasks.5.id}}` | Task 5 id | Yes | Yes | Reminders |  |  |
| `{{tasks.6.title}}` | Task 6 | Yes | Yes | Reminders |  |  |
| `{{tasks.6.due}}` | Task 6 due | Yes | Yes | Reminders |  |  |
| `{{tasks.6.done}}` | Task 6 done | Yes | Yes | Reminders |  |  |
| `{{tasks.6.id}}` | Task 6 id | Yes | Yes | Reminders |  |  |
| `task.toggle` | Complete task | Yes | Yes | Reminders |  |  |
| `task.add` | Add a task | Yes | Yes |  |  |  |

## Now playing

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{media.title}}` | Song title | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only: iOS has no API for other players' now playing. |
| `{{media.artist}}` | Artist | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.album}}` | Album | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.app}}` | Player app | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Always Music. |
| `{{media.playing}}` | Is playing | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.symbol}}` | Play/pause icon | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.elapsed}}` | Elapsed | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.duration}}` | Track length | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.remaining}}` | Time left | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.progress}}` | Track progress | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.artwork}}` | Album art | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music only. |
| `{{media.appIcon}}` | Playing app icon | No | Yes |  | Notification access (now playing from any player) | iOS: iOS doesn't tell other apps which app is playing; the icon shows a music note. |
| `media.playPause` | Play/pause | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music in the widget; with arg "shortcut" any player through a Shortcut. |
| `media.next` | Next track | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music in the widget; with arg "shortcut" any player through a Shortcut. |
| `media.previous` | Previous track | Yes | Yes | Apple Music | Notification access (now playing from any player) | iOS: Apple Music in the widget; with arg "shortcut" any player through a Shortcut. |
| `media.open` | Open the player | Yes | Yes |  |  |  |

## Volume and brightness

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{volume.level}}` | Media volume | Yes | Yes |  |  |  |
| `{{volume.ring}}` | Ringer volume | No | Yes |  |  | iOS: iOS has no API for the ringer volume. |
| `{{volume.muted}}` | Muted | Yes | Yes |  |  |  |
| `{{volume.symbol}}` | Volume icon | Yes | Yes |  |  |  |
| `{{brightness.level}}` | Brightness | No | Yes |  |  | iOS: A widget can't read the brightness. |
| `volume.up` | Volume up | Shortcut | Yes | A Shortcut you create once |  |  |
| `volume.down` | Volume down | Shortcut | Yes | A Shortcut you create once |  |  |
| `volume.mute` | Mute | Shortcut | Yes | A Shortcut you create once |  |  |
| `volume.ringUp` | Ringer up | No | Yes |  |  |  |
| `volume.ringDown` | Ringer down | No | Yes |  |  |  |
| `brightness.up` | Brightness up | Shortcut | Yes | A Shortcut you create once | Modify system settings |  |
| `brightness.down` | Brightness down | Shortcut | Yes | A Shortcut you create once | Modify system settings |  |
| `captions.toggle` | Live captions | Shortcut | System panel | A Shortcut you create once |  |  |

## System switches

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{compass.north}}` | North arrow angle | No | Yes |  |  | iOS: A widget can't read the compass; a tap opens the live compass. Android: Read when the widget redraws (once a minute); a tap opens the live compass. |
| `{{compass.heading}}` | Compass heading | No | Yes |  |  | iOS: A widget can't read the compass; a tap opens the live compass. Android: Read when the widget redraws (once a minute); a tap opens the live compass. |
| `{{system.wifi}}` | Wi-Fi is on | Yes | Yes |  |  | iOS: 1 only while connected to Wi-Fi. |
| `{{system.bluetooth}}` | Bluetooth is on | No | Yes |  |  | iOS: A widget can't read it; the switch keeps its off look. |
| `{{system.airplane}}` | Airplane mode is on | No | Yes |  |  | iOS: A widget can't read it; the switch keeps its off look. |
| `{{system.mobileData}}` | Mobile data is on | Yes | Yes |  |  | iOS: 1 only while using cellular. |
| `{{system.darkMode}}` | Dark mode is on | Yes | Yes |  |  |  |
| `{{system.lowPower}}` | Low power mode is on | Yes | Yes |  |  |  |
| `{{system.silent}}` | Silent is on | No | Yes |  |  | iOS: A widget can't read it; the switch keeps its off look. |
| `{{system.rotationLock}}` | Rotation is locked | No | Yes |  |  | iOS: A widget can't read it; the switch keeps its off look. |
| `{{system.dnd}}` | Do Not Disturb is on | No | Yes |  |  | iOS: A widget can't read it; the switch keeps its off look. |
| `{{system.torch}}` | Torch is on | No | Yes |  |  | iOS: A widget can't read it; the switch keeps its off look. |
| `system.toggle.torch` | Torch | Shortcut | Yes | A Shortcut you create once |  |  |
| `system.toggle.wifi` | Wi-Fi | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.bluetooth` | Bluetooth | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.airplane` | Airplane mode | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.mobileData` | Mobile data | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.darkMode` | Dark mode | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.lowPower` | Low power mode | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.silent` | Silent | Shortcut | Yes | A Shortcut you create once | Do Not Disturb access |  |
| `system.toggle.rotation` | Auto-rotate | Shortcut | Yes | A Shortcut you create once | Modify system settings |  |
| `system.toggle.dnd` | Do Not Disturb | Shortcut | Yes | A Shortcut you create once | Do Not Disturb access |  |
| `system.toggle.hotspot` | Hotspot | Shortcut | System panel | A Shortcut you create once |  |  |
| `system.toggle.nfc` | NFC | No | System panel |  |  | iOS: iPhone NFC has no switch. |

## Your own values

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{field.<key>}}` | Your text | Yes | Yes |  |  |  |

## Open

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{app.<appField>.icon}}` | An app's icon | No | Yes |  |  | iOS: iOS doesn't give apps other apps' icons; pick a picture instead. |
| `open.app` | Open Widget Studio | Yes | Yes |  |  |  |
| `open.url` | Open a link | Yes | Yes |  |  |  |
| `open.deeplink` | Open an app link | Yes | Yes |  |  |  |
| `app.launch` | Open an installed app | No | Yes |  |  | iOS: Use Open an app link instead. |
| `call.dial` | Call a number | Yes | Yes |  |  |  |
| `message.open` | Message a number | Yes | Yes |  |  |  |
| `shortcut.run` | Run a Shortcut | Shortcut | System panel | A Shortcut you create once |  | Android: Common names (Wi-Fi, Torch…) map to Android; others show a hint. |
| `camera.open` | Open the camera | Shortcut | Yes | A Shortcut you create once |  |  |
| `qr.scan` | Scan a QR code | Shortcut | Yes | A Shortcut you create once |  |  |
| `calendar.open` | Open the calendar | Yes | Yes |  |  |  |
| `reminders.open` | Open Reminders | Yes | No |  |  |  |
| `compass.open` | Open the live compass | Yes | Yes |  |  |  |
| `weather.open` | Open the weather | Yes | System panel |  |  | Android: Opens the web forecast for your place. |
| `assistant.open` | Open the assistant | Shortcut | Yes | A Shortcut you create once |  |  |
| `screen.record` | Record the screen | No | No |  |  |  |
| `search.open` | Search | No | Yes |  |  | iOS: iOS can't open Search from an app. |
| `alarm.open` | Open alarms | Yes | Yes |  |  |  |
| `clock.open` | Open the clock | Yes | Yes |  |  |  |
| `health.open` | Open health | Yes | Yes |  |  |  |

## Stocks and coins

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{stock.<tickerField>.price}}` | Price | Yes | Yes |  |  |  |
| `{{stock.<tickerField>.change}}` | Change | Yes | Yes |  |  |  |
| `{{stock.<tickerField>.changePct}}` | Change % | Yes | Yes |  |  |  |
| `{{stock.<tickerField>.series}}` | Price history | Yes | Yes |  |  |  |

## Screen time and earbuds

| Id | What | iOS | Android | iOS needs | Android needs | Notes |
|---|---|---|---|---|---|---|
| `{{screenTime.today}}` | Screen time today | No | Yes |  | Usage access (screen time) | iOS: iOS keeps screen time to Apple's Screen Time; apps need a special entitlement. |
| `{{earbuds.level}}` | Earbuds battery | No | Yes |  | Nearby devices (earbuds battery) | iOS: iOS doesn't share AirPods battery with apps. |
| `{{earbuds.left}}` | Left earbud | No | No |  |  | iOS: Not shared with apps. Android: Android shares one level per headset, not per earbud: use Earbuds battery. |
| `{{earbuds.right}}` | Right earbud | No | No |  |  | iOS: Not shared with apps. Android: Android shares one level per headset, not per earbud: use Earbuds battery. |
| `{{earbuds.case}}` | Earbuds case | No | No |  |  | iOS: Not shared with apps. Android: Android shares one level per headset, not per earbud: use Earbuds battery. |
