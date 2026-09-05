import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { compareBaseline, loadBaseline, loadInventory, readRepositoryFile, validateInventory } from '../../scripts/verify_feature_continuity.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readRepositoryFile(root, path);
const catalog = JSON.parse(read('config/module_catalog.json'));
const inventory = () => loadInventory(read);
const validate = value => validateInventory(value, catalog, read);

test('the complete checked-in register has valid owners and source evidence', () => validate(inventory()));
test('an unchanged register preserves every source and capability', () => compareBaseline(inventory(), inventory(), read));

test('removing one previous capability is rejected even if all remaining rows validate', () => {
  const previous = inventory(); const current = inventory();
  current.features.pop();
  validate(current);
  assert.throws(() => compareBaseline(current, previous, read), /feature removed/);
});

test('removing a source with an unresolved discovery gap cannot hide the gap', () => {
  const previous = inventory(); const current = inventory();
  current.index.sources = current.index.sources.filter(source => source.id !== 'historical_trade_alias');
  validate(current);
  assert.throws(() => compareBaseline(current, previous, read), /source removed/);
});

test('an unknown owner cannot silently create a new authority', () => {
  const value = inventory(); value.features[0].target_owner = 'invented.owner';
  assert.throws(() => validate(value), /Unknown target owner/);
});

test('legacy runtime claims cannot qualify the target without target evidence', () => {
  const value = inventory(); value.features[0].target_status = 'qualified';
  assert.throws(() => validate(value), /qualified target revision/);
  value.features[0].qualified_revision = value.index.target_baseline_revision;
  assert.throws(() => validate(value), /lacks tests evidence/);
});

test('qualification requires runtime, reconciliation and rollback evidence as well as tests', () => {
  const value = inventory(); const feature = value.features[0];
  feature.target_status = 'qualified'; feature.qualified_revision = value.index.target_baseline_revision;
  feature.target_evidence = [{ kind: 'tests', path: 'test/architecture/feature_continuity_test.mjs', description: 'Synthetic validator fixture only' }];
  assert.throws(() => validate(value), /lacks runtime evidence/);
});

test('unresolved ownership and incomplete discovery remain blocked', () => {
  const value = inventory(); value.features.find(feature => feature.integration_mode === 'ownership_review').target_status = 'planned';
  assert.throws(() => validate(value), /Unresolved ownership/);
  const full = inventory(); full.index.coverage_status = 'complete';
  assert.throws(() => validate(full), /Coverage gap/);
});

test('changing an obligation requires a recorded decision', () => {
  const old = inventory(); const next = inventory(); next.features[0].required_outcome = 'Reduced behavior';
  assert.throws(() => compareBaseline(next, old, read), /needs a decision/);
  next.features[0].change_decision = next.index.decision_ref;
  compareBaseline(next, old, read);
});

test('acceptance criteria cannot be silently weakened in place', () => {
  const old = inventory(); const next = inventory(); next.index.acceptance_profiles.planning.pop();
  assert.throws(() => compareBaseline(next, old, read), /acceptance criteria changed/);
});

test('duplicate ids and fabricated evidence paths fail', () => {
  const duplicate = inventory(); duplicate.features.push(duplicate.features[0]);
  assert.throws(() => validate(duplicate), /Duplicate feature/);
  const traversal = inventory(); traversal.features[0].source_evidence.path = '../outside';
  assert.throws(() => validate(traversal), /Unsafe path/);
});

test('catalog reads reject traversal, oversized files and symlinks outside the repository', () => {
  const temporary = mkdtempSync(resolve(tmpdir(), 'uok-continuity-'));
  const directory = resolve(temporary, 'repo'); mkdirSync(directory);
  writeFileSync(resolve(temporary, 'outside'), 'outside');
  writeFileSync(resolve(directory, 'large'), 'x'.repeat(1024 * 1024 + 1));
  symlinkSync(resolve(temporary, 'outside'), resolve(directory, 'escape'));
  try {
    assert.throws(() => readRepositoryFile(directory, '../outside'), /Unsafe path/);
    assert.throws(() => readRepositoryFile(directory, 'large'), /bounded regular file/);
    assert.throws(() => readRepositoryFile(directory, 'escape'), /leaves repository/);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
});

test('baseline lookup validates the commit and handles first adoption explicitly', () => {
  assert.equal(loadBaseline(root, inventory().index.target_baseline_revision), null);
  assert.throws(() => loadBaseline(root, '--output=unsafe'), /full commit SHA/);
  assert.throws(() => loadBaseline(root, 'f'.repeat(40)));
});
