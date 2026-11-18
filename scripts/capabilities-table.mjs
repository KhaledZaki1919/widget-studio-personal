// Writes docs/capabilities.md from the catalog (ADR-027): node scripts/capabilities-table.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const file = new URL('../ios/WidgetKitCore/Sources/WidgetKitCore/Resources/Spec/capabilities.json', import.meta.url);
const catalog = JSON.parse(readFileSync(file, 'utf8'));
const label = { native: 'Yes', shortcut: 'Shortcut', panel: 'System panel', unsupported: 'No' };
const on = (value, platform) => (value && typeof value === 'object' ? value[platform] : value) ?? null;
const support = (entry, platform) => label[on(entry.support, platform) ?? 'native'];
const permission = (entry, platform) => {
  const id = on(entry.permission, platform);
  return id ? catalog.permissions.find((item) => item.id === id).title.en : '';
};
const note = (entry) => [on(entry.note, 'ios') && `iOS: ${on(entry.note, 'ios')}`, on(entry.note, 'android') && `Android: ${on(entry.note, 'android')}`]
  .filter(Boolean).join(' ').replace(/\|/g, '/');
const rows = (entries, code) => entries.map((entry) =>
  `| ${code(entry)} | ${entry.title.en} | ${support(entry, 'ios')} | ${support(entry, 'android')} | ${permission(entry, 'ios')} | ${permission(entry, 'android')} | ${note(entry)} |`);
const header = ['| Id | What | iOS | Android | iOS needs | Android needs | Notes |', '|---|---|---|---|---|---|---|'];
const lines = ['# Capabilities', '', 'Generated from `capabilities.json` by `scripts/capabilities-table.mjs`. Do not edit by hand.', ''];
for (const group of catalog.groups) {
  const bindings = catalog.bindings.filter((entry) => entry.group === group.id);
  const actions = catalog.actions.filter((entry) => entry.group === group.id);
  if (!bindings.length && !actions.length) continue;
  lines.push(`## ${group.title.en}`, '', ...header, ...rows(bindings, (entry) => `\`{{${entry.id}}}\``), ...rows(actions, (entry) => `\`${entry.id}\``), '');
}
writeFileSync(new URL('../docs/capabilities.md', import.meta.url), lines.join('\n'));
console.log(catalog.bindings.length, 'bindings,', catalog.actions.length, 'actions');
