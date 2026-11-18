#!/usr/bin/env node
// Writes the built-in state sets into capabilities.json (ADR-028). The dot art lives here as ASCII
// maps: `A` is the accent color, `C` the main color, `.` an unlit dot. Each map becomes up to two
// dotGrid layers, the only primitive both renderers draw identically at every size. Colors stay
// `$color`, `$accent`, `$dim` until a layer picks them. Run: node scripts/state-art.mjs
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const file = path.join(root, 'ios/WidgetKitCore/Sources/WidgetKitCore/Resources/Spec/capabilities.json');

/** One 16 × 16 map as dotGrid layers in a 100 × 100 box, accent dots last so they sit on top. */
function art(map) {
  const rows = map.trim().split('\n').map((row) => row.trim());
  if (rows.length !== 16 || rows.some((row) => row.length !== 16)) throw new Error('map must be 16 × 16:\n' + map);
  const grid = (mark, color) => {
    const values = rows.join('').replace(new RegExp(`[^${mark}]`, 'g'), '0').replaceAll(mark, '1');
    if (!values.includes('1')) return [];
    return [{ type: 'dotGrid', frame: { x: 0, y: 0, w: 100, h: 100 }, rows: 16, cols: 16, dotSize: 5.2, gap: 1.2, onColor: color, offColor: '#00000000', values }];
  };
  return [...grid('C', '$color'), ...grid('A', '$accent')];
}

const face = {
  laughing: `
.....CCCCCC.....
...CC......CC...
..C..........C..
.C............C.
.C...C....C...C.
C...C.C..C.C...C
C..............C
C..............C
C...CCCCCCCC...C
C...CCCCCCCC...C
C....CCAACC....C
.C....CAAC....C.
.C............C.
..C..........C..
...CC......CC...
.....CCCCCC.....`,
  happy: `
.....CCCCCC.....
...CC......CC...
..C..........C..
.C............C.
.C............C.
C...CC....CC...C
C...CC....CC...C
C..............C
C..............C
C...C......C...C
C....C....C....C
.C....CCCC....C.
.C............C.
..C..........C..
...CC......CC...
.....CCCCCC.....`,
  normal: `
.....CCCCCC.....
...CC......CC...
..C..........C..
.C............C.
.C............C.
C...CC....CC...C
C...CC....CC...C
C..............C
C..............C
C..............C
C....CCCCCC....C
.C............C.
.C............C.
..C..........C..
...CC......CC...
.....CCCCCC.....`,
  worried: `
.....CCCCCC.....
...CC......CC...
..C..........C..
.C...CC..CC...C.
.C..C......C..C.
C..............C
C...CC....CC...C
C...CC....CC...C
C..............C
C..............C
C....CC..CC....C
.C.....CC.....C.
.C............C.
..C..........C..
...CC......CC...
.....CCCCCC.....`,
  sad: `
.....CCCCCC.....
...CC......CC...
..C..........C..
.C............C.
.C............C.
C...CC....CC...C
C...CC....CC...C
C..........A...C
C..........A...C
C.....CCCC.....C
C....C....C....C
.C..C......C..C.
.C............C.
..C..........C..
...CC......CC...
.....CCCCCC.....`,
};

const sky = {
  sun: `
................
.......AA.......
.A.....AA.....A.
..A..........A..
.....AAAAAA.....
....AAAAAAAA....
....AAAAAAAA....
AA..AAAAAAAA..AA
AA..AAAAAAAA..AA
....AAAAAAAA....
....AAAAAAAA....
.....AAAAAA.....
..A..........A..
.A.....AA.....A.
.......AA.......
................`,
  moon: `
................
.......CCCC...A.
.....CCCC....AAA
....CCCC......A.
...CCCC.........
...CCCC.........
..CCCCC.........
..CCCCC.........
..CCCCCC........
..CCCCCCC.....C.
...CCCCCCCC..CC.
...CCCCCCCCCCCC.
....CCCCCCCCCC..
.....CCCCCCCC...
.......CCCC.....
................`,
  partlyDay: `
..A...A.........
.....AAA........
....AAAAA.......
A..AAAAAAA......
...AAAAACCCC....
....AAACCCCCC...
.....CCCCCCCCCC.
....CCCCCCCCCCCC
...CCCCCCCCCCCCC
..CCCCCCCCCCCCCC
..CCCCCCCCCCCCCC
..CCCCCCCCCCCCCC
...CCCCCCCCCCCC.
................
................
................`,
  partlyNight: `
.......AAA......
.....AAAA.......
....AAAA......A.
....AAAA.....AAA
....AAAACCCC..A.
.....AACCCCCC...
.....CCCCCCCCCC.
....CCCCCCCCCCCC
...CCCCCCCCCCCCC
..CCCCCCCCCCCCCC
..CCCCCCCCCCCCCC
..CCCCCCCCCCCCCC
...CCCCCCCCCCCC.
................
................
................`,
  cloud: `
................
................
................
................
.....CCCC.......
....CCCCCC.CC...
...CCCCCCCCCCC..
..CCCCCCCCCCCCC.
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
..CCCCCCCCCCCCC.
................
................
................`,
  rain: `
................
.....CCCC.......
....CCCCCC.CC...
...CCCCCCCCCCC..
..CCCCCCCCCCCCC.
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
..CCCCCCCCCCCCC.
................
...A...A...A....
...A...A...A....
.A...A...A...A..
.A...A...A...A..
................
................`,
  storm: `
................
.....CCCC.......
....CCCCCC.CC...
...CCCCCCCCCCC..
..CCCCCCCCCCCCC.
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
..CCCCCCCCCCCCC.
.......AAA......
......AAA.......
.....AAAAAA.....
........AA......
.......AA.......
.......A........
................`,
  snow: `
................
.....CCCC.......
....CCCCCC.CC...
...CCCCCCCCCCC..
..CCCCCCCCCCCCC.
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
..CCCCCCCCCCCCC.
................
..A....A....A...
.AAA..AAA..AAA..
..A....A....A...
................
.....A....A.....
................`,
  fog: `
................
................
.....CCCC.......
....CCCCCC.CC...
...CCCCCCCCCCC..
..CCCCCCCCCCCCC.
.CCCCCCCCCCCCCCC
.CCCCCCCCCCCCCCC
................
..AAAAAAAAAAAA..
................
AAAAAAAAAAAAAAAA
................
...AAAAAAAAAA...
................
................`,
};

const icon = (symbol, color, size = 80) => ({ type: 'icon', frame: { x: 0, y: 0, w: 100, h: 100 }, symbol, size, color });
const t = (en, ar) => ({ en, ar });

const stateSets = [
  {
    id: 'battery.mood', title: t('Battery mood', 'مزاج البطارية'),
    description: 'a face that follows the battery: laughing while charging, happy, normal, worried, sad',
    box: [100, 100], topic: 'battery', needs: ['battery.level', 'battery.charging'],
    keywords: ['face', 'smiley', 'smile', 'mood', 'emoji', 'وجه', 'مزاج', 'ابتسامة'],
    glyphs: ['😀', '😃', '😄', '😁', '😆', '🙂', '😊', '😐', '😟', '😢', '🙁', '☹', '☺'],
    variants: [
      { id: 'charging', title: t('Charging', 'يشحن'), when: '{{battery.charging}}', sample: { 'battery.charging': '1', 'battery.level': '0.6' }, layers: art(face.laughing) },
      { id: 'full', title: t('90% or more', '90٪ أو أكثر'), when: '{{battery.level}} >= 0.9', sample: { 'battery.charging': '0', 'battery.level': '0.95' }, layers: art(face.happy) },
      { id: 'normal', title: t('50 to 89%', 'من 50 إلى 89٪'), when: '{{battery.level}} >= 0.5', sample: { 'battery.charging': '0', 'battery.level': '0.7' }, layers: art(face.normal) },
      { id: 'worried', title: t('21 to 49%', 'من 21 إلى 49٪'), when: '{{battery.level}} > 0.2', sample: { 'battery.charging': '0', 'battery.level': '0.35' }, layers: art(face.worried) },
      { id: 'sad', title: t('20% or less', '20٪ أو أقل'), sample: { 'battery.charging': '0', 'battery.level': '0.12' }, layers: art(face.sad) },
    ],
  },
  {
    id: 'weather.art', title: t('Weather illustration', 'رسمة الطقس'),
    description: 'a big dot drawing of the current weather: sun, moon, partly cloudy, cloud, rain, storm, snow, fog',
    box: [100, 100], topic: 'weather', needs: ['weather.kind', 'time.isDay'],
    keywords: ['illustration', 'drawing', 'dot art', 'pixel art', 'رسمة', 'رسم'],
    variants: [
      { id: 'storm', title: t('Storm', 'عاصفة'), when: '{{weather.kind}} == storm', sample: { 'weather.kind': 'storm' }, layers: art(sky.storm) },
      { id: 'snow', title: t('Snow', 'ثلج'), when: '{{weather.kind}} == snow', sample: { 'weather.kind': 'snow' }, layers: art(sky.snow) },
      { id: 'rain', title: t('Rain', 'مطر'), when: '{{weather.kind}} == rain', sample: { 'weather.kind': 'rain' }, layers: art(sky.rain) },
      { id: 'fog', title: t('Fog', 'ضباب'), when: '{{weather.kind}} == fog', sample: { 'weather.kind': 'fog' }, layers: art(sky.fog) },
      { id: 'cloud', title: t('Cloudy', 'غائم'), when: '{{weather.kind}} == cloudy', sample: { 'weather.kind': 'cloudy' }, layers: art(sky.cloud) },
      { id: 'partlyDay', title: t('Partly cloudy', 'غائم جزئيًا'), when: '{{weather.kind}} == partlyCloudy && {{time.isDay}}', sample: { 'weather.kind': 'partlyCloudy', 'time.isDay': '1' }, layers: art(sky.partlyDay) },
      { id: 'partlyNight', title: t('Partly cloudy, night', 'غائم جزئيًا ليلًا'), when: '{{weather.kind}} == partlyCloudy', sample: { 'weather.kind': 'partlyCloudy', 'time.isDay': '0' }, layers: art(sky.partlyNight) },
      { id: 'sun', title: t('Sunny', 'مشمس'), when: '{{weather.kind}} == clear && {{time.isDay}}', sample: { 'weather.kind': 'clear', 'time.isDay': '1' }, layers: art(sky.sun) },
      { id: 'moon', title: t('Clear night', 'ليل صافٍ'), when: '{{weather.kind}} == clear', sample: { 'weather.kind': 'clear', 'time.isDay': '0' }, layers: art(sky.moon) },
    ],
  },
  {
    id: 'day.night', title: t('Day and night', 'النهار والليل'),
    description: 'a sun by day, a moon at night', box: [100, 100], topic: 'time', needs: ['time.isDay'],
    keywords: ['day and night', 'sun and moon', 'نهار', 'ليل'],
    variants: [
      { id: 'day', title: t('Day', 'نهار'), when: '{{time.isDay}}', sample: { 'time.isDay': '1' }, layers: [icon('sun.max.fill', '$accent')] },
      { id: 'night', title: t('Night', 'ليل'), sample: { 'time.isDay': '0' }, layers: [icon('moon.stars.fill', '$color')] },
    ],
  },
  {
    id: 'task.done', title: t('Task done', 'إنجاز المهمة'),
    description: 'a checkbox: set value to a task row, like {{tasks.1.done}}', box: [100, 100], value: '{{tasks.1.done}}', topic: 'tasks',
    keywords: ['checkbox', 'check box', 'to do', 'مربع اختيار'],
    variants: [
      { id: 'done', title: t('Done', 'منجزة'), when: '$value', sample: { $value: '1' }, layers: [icon('checkmark.circle.fill', '$accent')] },
      { id: 'open', title: t('Not done', 'غير منجزة'), sample: { $value: '0' }, layers: [{ type: 'shape', frame: { x: 12, y: 12, w: 76, h: 76 }, kind: 'circle', stroke: { color: '$color', width: 8 } }] },
    ],
  },
  {
    id: 'media.playing', title: t('Playing or paused', 'تشغيل أو إيقاف'),
    description: 'a pause mark while playing, a play mark when paused', box: [100, 100], topic: 'media', needs: ['media.playing'],
    keywords: ['play button', 'pause button', 'زر التشغيل'],
    variants: [
      { id: 'playing', title: t('Playing', 'يعمل'), when: '{{media.playing}}', sample: { 'media.playing': '1' }, layers: [icon('pause.fill', '$color')] },
      { id: 'paused', title: t('Paused', 'متوقف'), sample: { 'media.playing': '0' }, layers: [icon('play.fill', '$color')] },
    ],
  },
  {
    id: 'toggle.onoff', title: t('On or off', 'تشغيل أو إيقاف المفتاح'),
    description: 'a switch: set value to a state, like {{system.wifi}}', box: [100, 60], value: '{{system.wifi}}', topic: 'system',
    keywords: ['switch', 'toggle', 'مفتاح'],
    variants: [
      { id: 'on', title: t('On', 'مفعّل'), when: '$value', sample: { $value: '1' }, layers: [
        { type: 'shape', frame: { x: 0, y: 0, w: 100, h: 60 }, kind: 'capsule', fill: '$accent' },
        { type: 'shape', frame: { x: 46, y: 6, w: 48, h: 48 }, kind: 'circle', fill: '#FFFFFF' },
      ] },
      { id: 'off', title: t('Off', 'متوقف'), sample: { $value: '0' }, layers: [
        { type: 'shape', frame: { x: 0, y: 0, w: 100, h: 60 }, kind: 'capsule', fill: '$dim' },
        { type: 'shape', frame: { x: 6, y: 6, w: 48, h: 48 }, kind: 'circle', fill: '$color' },
      ] },
    ],
  },
  {
    id: 'goal.reached', title: t('Goal reached', 'تحقق الهدف'),
    description: 'a target until a progress value reaches 1, then a check: set value, like {{steps.progress}}', box: [100, 100], value: '{{steps.progress}}',
    keywords: ['goal', 'target', 'الهدف'],
    variants: [
      { id: 'reached', title: t('Reached', 'تحقق'), when: '$value >= 1', sample: { $value: '1' }, layers: [icon('checkmark.circle.fill', '$accent')] },
      { id: 'going', title: t('Not yet', 'لم يتحقق'), sample: { $value: '0.4' }, layers: [icon('flame.fill', '$color')] },
    ],
  },
  {
    id: 'level.band', title: t('Low, normal, high', 'منخفض وعادي ومرتفع'),
    description: 'three rising bars lit by level: set value to a 0…1 binding, like {{volume.level}}', box: [100, 100], value: '{{volume.level}}',
    keywords: ['level', 'bars', 'مستوى'],
    variants: ['low', 'normal', 'high'].map((id, index) => ({
      id,
      title: [t('Low', 'منخفض'), t('Normal', 'عادي'), t('High', 'مرتفع')][index],
      when: ['$value <= 0.2', '$value < 0.7', undefined][index],
      sample: { $value: ['0.1', '0.5', '0.9'][index] },
      layers: [0, 1, 2].map((bar) => ({
        type: 'shape', frame: { x: 8 + bar * 30, y: 64 - bar * 28, w: 24, h: 28 + bar * 28 }, kind: 'roundedRect', cornerRadius: 6, fill: bar <= index ? (index === 0 ? '$accent' : '$color') : '$dim',
      })),
    })),
  },
];

const cap = (id, group, type, en, ar, description, example, keywords, layers, extra = {}) => ({ id, group, type, title: t(en, ar), description, example, keywords, layers, ...extra });
const share = ['text', 'ring', 'progressBar', 'dotGrid'];
const timeWords = {
  year: ['year', 'yearly', 'annual', 'سنة', 'السنة', 'العام', 'عام'],
  month: ['month', 'monthly', 'شهر', 'الشهر'],
  week: ['week', 'weekly', 'أسبوع', 'الأسبوع'],
  day: ['day', 'daily', 'يوم', 'اليوم'],
};
const newTime = [
  cap('year.progress', 'time', 'number', 'Year progress', 'تقدم السنة', 'share of the year gone, 0…1 (ring, bar or dots); shows 85 in text, add %', '0.85', timeWords.year, share),
  cap('month.progress', 'time', 'number', 'Month progress', 'تقدم الشهر', 'share of the month gone, 0…1; shows 16 in text, add %', '0.16', timeWords.month, share),
  cap('week.progress', 'time', 'number', 'Week progress', 'تقدم الأسبوع', 'share of the week gone, 0…1; shows 72 in text, add %', '0.72', timeWords.week, share),
  cap('day.progress', 'time', 'number', 'Day progress', 'تقدم اليوم', 'share of today gone, 0…1; shows 45 in text, add %', '0.45', timeWords.day, share),
  cap('year.day', 'time', 'number', 'Day of the year', 'اليوم من السنة', 'day number in the year, 1…366', '309', ['day of year', 'day of the year', 'اليوم من السنة'], ['text']),
  cap('year.daysLeft', 'time', 'number', 'Days left in the year', 'الأيام المتبقية من السنة', 'days until the year ends', '56', ['days left in the year', 'days left this year', 'متبقي من السنة'], ['text']),
  cap('month.daysLeft', 'time', 'number', 'Days left in the month', 'الأيام المتبقية من الشهر', 'days until the month ends', '25', ['days left in the month', 'days left this month', 'متبقي من الشهر'], ['text']),
  cap('week.daysLeft', 'time', 'number', 'Days left in the week', 'الأيام المتبقية من الأسبوع', 'days until the week ends', '2', ['days left in the week', 'days left this week', 'متبقي من الأسبوع'], ['text']),
  cap('time.isDay', 'time', 'bool', 'Daytime', 'النهار', '1 between sunrise and sunset', '1', ['daytime', 'day or night', 'نهار'], ['when']),
];
const newWeather = [
  cap('weather.kind', 'weather', 'text', 'Condition kind', 'نوع الطقس', 'for conditions: clear, partlyCloudy, cloudy, fog, rain, storm or snow', 'partlyCloudy', ['condition kind'], ['when']),
];
for (let day = 1; day <= 6; day++) {
  newWeather.push(
    cap(`forecast.${day}.day`, 'weather', 'text', `Forecast day ${day}`, `يوم التوقعات ${day}`, `short name of day ${day} from tomorrow`, 'Sat', [], ['text']),
    cap(`forecast.${day}.symbol`, 'weather', 'symbol', `Forecast icon ${day}`, `أيقونة التوقعات ${day}`, `that day's real condition icon`, 'cloud.sun.fill', [], ['icon']),
    cap(`forecast.${day}.hi`, 'weather', 'number', `Forecast high ${day}`, `العظمى ${day}`, `that day's high`, '31', [], ['text']),
    cap(`forecast.${day}.lo`, 'weather', 'number', `Forecast low ${day}`, `الصغرى ${day}`, `that day's low`, '20', [], ['text']),
  );
}
const taskWords = ['tasks', 'task', 'to do', 'todo', 'to-do', 'checklist', 'مهام', 'مهمة', 'المهام'];
const taskPerm = { permission: { ios: 'reminders' } };
const taskIcons = ['checkmark.circle.fill', 'list.bullet'];
const newTasks = [
  cap('tasks.list', 'tasks', 'text', 'Open tasks', 'المهام المفتوحة', 'the open tasks, one per line', 'Call the bank\nBuy milk', taskWords, ['text'], taskPerm),
  cap('tasks.today.count', 'tasks', 'number', 'Tasks today', 'مهام اليوم', 'open tasks due today or overdue', '3', taskWords, ['text'], taskPerm),
  cap('tasks.open.count', 'tasks', 'number', 'Open task count', 'عدد المهام المفتوحة', 'every open task', '5', taskWords, ['text'], taskPerm),
  cap('tasks.done.count', 'tasks', 'number', 'Tasks done today', 'المهام المنجزة اليوم', 'tasks completed today', '2', [...taskWords, 'done', 'منجزة'], ['text'], taskPerm),
  cap('tasks.progress', 'tasks', 'number', 'Task progress', 'تقدم المهام', "share of today's tasks done, 0…1 (ring or bar)", '0.4', taskWords, ['text', 'ring', 'progressBar', 'dotGrid'], taskPerm),
  cap('tasks.next.title', 'tasks', 'text', 'Next task', 'المهمة التالية', 'the next open task', 'Call the bank', taskWords, ['text'], { icons: taskIcons, ...taskPerm }),
  cap('tasks.next.due', 'tasks', 'text', 'Next task due', 'موعد المهمة التالية', 'when it is due, short', 'Today 14:30', taskWords, ['text'], taskPerm),
  cap('tasks.next.id', 'tasks', 'text', 'Next task id', 'معرّف المهمة التالية', 'the arg of task.toggle for that task', 'task-1', [], ['arg'], taskPerm),
];
for (let row = 1; row <= 6; row++) {
  newTasks.push(
    cap(`tasks.${row}.title`, 'tasks', 'text', `Task ${row}`, `المهمة ${row}`, `row ${row}: open tasks by due date, then today's done ones`, ['Call the bank', 'Buy milk', 'Gym', 'Pay rent', 'Read', 'Plan trip'][row - 1], taskWords, ['text'], taskPerm),
    cap(`tasks.${row}.due`, 'tasks', 'text', `Task ${row} due`, `موعد المهمة ${row}`, 'when it is due, short', 'Today', [], ['text'], taskPerm),
    cap(`tasks.${row}.done`, 'tasks', 'bool', `Task ${row} done`, `إنجاز المهمة ${row}`, '1 once completed; for task.done', row === 2 ? '1' : '0', [], ['when'], taskPerm),
    cap(`tasks.${row}.id`, 'tasks', 'text', `Task ${row} id`, `معرّف المهمة ${row}`, 'the arg of task.toggle for that row', `task-${row}`, [], ['arg'], taskPerm),
  );
}
const newActions = [
  { id: 'task.toggle', group: 'tasks', title: t('Complete task', 'إنجاز مهمة'), description: 'tick or untick a task inside the widget; arg is its id binding, like {{tasks.1.id}}', arg: 'optional', keywords: ['checkbox', 'complete', 'tick', 'إنجاز'], icons: ['checkmark.circle.fill'], permission: { ios: 'reminders' } },
  { id: 'task.add', group: 'tasks', title: t('Add a task', 'إضافة مهمة'), description: "open the app's quick add", keywords: ['add task', 'new task', 'أضف مهمة', 'مهمة جديدة'], icons: ['plus'] },
];

const catalog = JSON.parse(fs.readFileSync(file, 'utf8'));
const has = (id) => catalog.bindings.some((b) => b.id === id) || catalog.actions.some((a) => a.id === id);
catalog.version = 2;
if (!catalog.groups.some((g) => g.id === 'tasks')) {
  const index = catalog.groups.findIndex((g) => g.id === 'reminders');
  catalog.groups.splice(index + 1, 0, { id: 'tasks', title: t('Tasks', 'المهام') });
}
function insertAfter(list, anchor, items) {
  const fresh = items.filter((item) => !has(item.id));
  list.splice(list.findIndex((item) => item.id === anchor) + 1, 0, ...fresh);
}
insertAfter(catalog.bindings, 'days.<dateField>', newTime);
insertAfter(catalog.bindings, 'weather.city', newWeather);
insertAfter(catalog.bindings, 'reminders.4.title', newTasks);
insertAfter(catalog.actions, 'timer.reset', newActions);
catalog.stateSets = stateSets;

// One entry per line, as the file has always been laid out.
const line = (value) => '    ' + JSON.stringify(value).replace(/":/g, '": ').replace(/,"/g, ', "');
const section = (name, items) => `  "${name}": [\n${items.map(line).join(',\n')}\n  ]`;
const out = `{\n  "version": ${catalog.version},\n  "comment": ${JSON.stringify(catalog.comment)},\n` +
  ['permissions', 'groups', 'bindings', 'actions', 'stateSets'].map((name) => section(name, catalog[name])).join(',\n') + '\n}\n';
JSON.parse(out);
fs.writeFileSync(file, out);
console.log(`${catalog.bindings.length} bindings, ${catalog.actions.length} actions, ${stateSets.length} state sets`);
