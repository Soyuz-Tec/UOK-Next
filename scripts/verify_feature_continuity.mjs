import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, realpathSync, statSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const indexPath = 'config/feature_continuity.json';
const shaPattern = /^[a-f0-9]{40}$/;
const statuses = new Set(['planned', 'partial', 'blocked', 'qualified']);
const modes = new Set(['native', 'adapter', 'companion', 'ownership_review']);
const discoveryStates = new Set(['initial_inventory', 'inventory_gap', 'complete', 'not_application']);
const evidenceKinds = ['tests', 'runtime', 'reconciliation', 'rollback'];

function nonempty(value, context) {
  assert.equal(typeof value, 'string', `${context}: expected text`);
  assert(value.trim().length > 0, `${context}: empty text`);
}

function safePath(path) {
  nonempty(path, 'path');
  assert(!isAbsolute(path) && !path.includes('\\') && !path.includes(':'), `Unsafe path: ${path}`);
  assert(path.split('/').every(part => part && part !== '.' && part !== '..'), `Unsafe path: ${path}`);
  return path;
}

export function readRepositoryFile(root, path) {
  const resolved = realpathSync(resolve(root, safePath(path)));
  const rel = relative(realpathSync(root), resolved);
  assert(rel && rel !== '..' && !rel.startsWith('../') && !rel.startsWith('..\\') && !isAbsolute(rel), `Path leaves repository: ${path}`);
  const stat = statSync(resolved);
  assert(stat.isFile() && stat.size <= 1024 * 1024, `Not a bounded regular file: ${path}`);
  return readFileSync(resolved, 'utf8');
}

export function loadInventory(read) {
  const index = JSON.parse(read(indexPath));
  assert(Array.isArray(index.sources), 'Sources must be an array');
  const features = [];
  for (const source of index.sources) {
    if (!source.feature_file) continue;
    const file = JSON.parse(read(safePath(source.feature_file)));
    assert.equal(file.source_id, source.id, `Mismatched source file: ${source.id}`);
    assert(Array.isArray(file.features), `Features must be an array: ${source.id}`);
    features.push(...file.features.map(feature => ({ ...feature, source_id: source.id })));
  }
  return { index, features };
}

function validateSource(source, read) {
  assert(/^[a-z][a-z0-9_]*$/.test(source.id), `Invalid source id: ${source.id}`);
  assert(discoveryStates.has(source.discovery_status), `Invalid discovery state: ${source.id}`);
  nonempty(source.discovery_note, source.id);
  read(safePath(source.provenance_ref.split('#')[0]));
  if (source.feature_file) {
    assert(shaPattern.test(source.revision), `Source revision must be pinned: ${source.id}`);
    assert(source.feature_file.startsWith('config/feature_continuity/'), `Unexpected feature file: ${source.id}`);
  }
}

function validateFeature(feature, inventory, owners, read) {
  const { id } = feature;
  assert(id.startsWith(`${feature.source_id}.`) && /^[a-z0-9_.-]+$/.test(id), `Invalid feature id: ${id}`);
  for (const field of ['capability', 'required_outcome']) nonempty(feature[field], `${id}.${field}`);
  assert(owners.has(feature.target_owner), `Unknown target owner: ${id}`);
  assert(statuses.has(feature.target_status), `Unknown target status: ${id}`);
  assert(modes.has(feature.integration_mode), `Unknown integration mode: ${id}`);
  assert(Number.isInteger(feature.delivery_gate) && feature.delivery_gate >= 4 && feature.delivery_gate <= 8, `Invalid delivery gate: ${id}`);
  assert(inventory.index.acceptance_profiles[feature.acceptance_profile], `Unknown acceptance profile: ${id}`);
  safePath(feature.source_evidence.path);
  nonempty(feature.source_evidence.locator, `${id}.source locator`);
  nonempty(feature.source_evidence.reported_maturity, `${id}.source maturity`);
  assert(Array.isArray(feature.target_evidence), `Missing target evidence array: ${id}`);
  if (feature.integration_mode === 'ownership_review') assert.equal(feature.target_status, 'blocked', `Unresolved ownership cannot be delivered: ${id}`);
  if (feature.target_status !== 'qualified') return;
  assert(shaPattern.test(feature.qualified_revision), `Missing qualified target revision: ${id}`);
  for (const kind of evidenceKinds) {
    const receipt = feature.target_evidence.find(entry => entry.kind === kind);
    assert(receipt, `Qualified feature lacks ${kind} evidence: ${id}`);
    nonempty(receipt.description, `${id}.${kind}`);
    read(safePath(receipt.path));
    if (kind === 'tests') assert(receipt.path.startsWith('test/') || receipt.path.startsWith('web/'), `Test evidence must identify tests: ${id}`);
  }
}

export function validateInventory(inventory, catalog, read) {
  assert.equal(inventory.index.schema_version, 1, 'Unsupported inventory schema');
  assert(['initial_inventory', 'complete'].includes(inventory.index.coverage_status), 'Invalid coverage status');
  assert(shaPattern.test(inventory.index.target_baseline_revision), 'Target baseline must be pinned');
  nonempty(inventory.index.requirement, 'requirement');
  read(safePath(inventory.index.decision_ref));
  const owners = new Set([...catalog.modules, ...catalog.external_systems].map(owner => owner.id));
  const sourceIds = new Set();
  for (const source of inventory.index.sources) {
    assert(!sourceIds.has(source.id), `Duplicate source: ${source.id}`);
    sourceIds.add(source.id);
    validateSource(source, read);
    if (source.feature_file) assert(inventory.features.some(feature => feature.source_id === source.id), `Empty source inventory: ${source.id}`);
    if (inventory.index.coverage_status === 'complete') assert(['complete', 'not_application'].includes(source.discovery_status), `Coverage gap: ${source.id}`);
  }
  for (const [name, criteria] of Object.entries(inventory.index.acceptance_profiles)) {
    assert(Array.isArray(criteria) && criteria.length >= 2, `Insufficient acceptance profile: ${name}`);
    criteria.forEach(criterion => nonempty(criterion, name));
  }
  assert(inventory.features.length > 0, 'Feature inventory is empty');
  const ids = new Set();
  for (const feature of inventory.features) {
    assert(sourceIds.has(feature.source_id), `Unknown source: ${feature.id}`);
    assert(!ids.has(feature.id), `Duplicate feature: ${feature.id}`);
    ids.add(feature.id);
    validateFeature(feature, inventory, owners, read);
  }
}

export function compareBaseline(current, previous, read) {
  const sources = new Set(current.index.sources.map(source => source.id));
  for (const source of previous.index.sources) assert(sources.has(source.id), `Previously inventoried source removed: ${source.id}`);
  const byId = new Map(current.features.map(feature => [feature.id, feature]));
  for (const old of previous.features) {
    const next = byId.get(old.id);
    assert(next, `Previously inventoried feature removed: ${old.id}`);
    const changed = ['required_outcome', 'target_owner', 'integration_mode', 'acceptance_profile'].some(key => next[key] !== old[key]);
    const regressed = old.target_status === 'qualified' && next.target_status !== 'qualified';
    if (!changed && !regressed) continue;
    assert(next.change_decision?.startsWith('docs/adr/'), `Changed obligation needs a decision: ${old.id}`);
    read(safePath(next.change_decision));
  }
  for (const [name, criteria] of Object.entries(previous.index.acceptance_profiles)) {
    assert.deepEqual(current.index.acceptance_profiles[name], criteria, `Existing acceptance criteria changed: ${name}; add a versioned profile and record an ADR instead`);
  }
}

function git(root, args) {
  return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8', stdio: 'pipe', maxBuffer: 1024 * 1024 });
}

export function loadBaseline(root, revision) {
  assert(shaPattern.test(revision), 'Baseline must be a full commit SHA');
  git(root, ['cat-file', '-e', `${revision}^{commit}`]);
  if (!git(root, ['ls-tree', '--name-only', revision, '--', indexPath]).trim()) return null;
  return loadInventory(path => git(root, ['show', `${revision}:${safePath(path)}`]));
}

function baselineRevision(args) {
  if (args.length) {
    assert(args.length === 2 && args[0] === '--baseline-ref', 'Usage: node scripts/verify_feature_continuity.mjs [--baseline-ref COMMIT]');
    return args[1];
  }
  if (!process.env.GITHUB_EVENT_PATH) return null;
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const revision = event.pull_request?.base?.sha ?? event.before;
  assert(revision && revision !== '0'.repeat(40), 'CI requires an existing base commit for retention verification');
  return revision;
}

export function main(root, args = []) {
  const read = path => readRepositoryFile(root, path);
  const current = loadInventory(read);
  validateInventory(current, JSON.parse(read('config/module_catalog.json')), read);
  const revision = baselineRevision(args);
  if (revision) {
    const previous = loadBaseline(root, revision);
    if (previous) compareBaseline(current, previous, read);
    console.log(previous ? `Retention compared with ${revision}.` : `Initial inventory: no prior register at ${revision}.`);
  } else console.log('No baseline supplied; schema validated. CI also checks feature retention.');
  const qualified = current.features.filter(feature => feature.target_status === 'qualified').length;
  console.log(`Validated ${current.features.length} capability entries across ${current.index.sources.length} source records; ${qualified} qualified in this register.`);
  console.log(`Discovery: ${current.index.coverage_status}. This check does not prove runtime feature parity.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(resolve(dirname(fileURLToPath(import.meta.url)), '..'), process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
