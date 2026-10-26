// NKI Importer - macOS GUI helper (JavaScript for Automation).
// Launched in the background by the Lua scripts, so REAPER's main thread stays free
// to process the clicks/keys we send to Kontakt:
//   osascript -l JavaScript nki_helper.js <mode> <job.json> <status.txt>
// modes: check | calibrate | load | dragfiles
// Progress is written to <status.txt> one line per step; the last line is DONE or ERROR: ...

ObjC.import('Foundation');
ObjC.import('AppKit');
ObjC.import('CoreGraphics');
ObjC.import('ApplicationServices');
ObjC.bindFunction('CGPreflightPostEventAccess', ['bool', []]);
ObjC.bindFunction('CGRequestPostEventAccess', ['bool', []]);

var se = Application('System Events');
var statusPath;
var logLines = [];

// ---------------------------------------------------------------- utils

function readText(path) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return s.isNil() ? null : s.js;
}

function writeText(path, text) {
  $(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}

var startTime = Date.now();

function status(line) {
  if (/^STEP/.test(line)) line += '  [' + ((Date.now() - startTime) / 1000).toFixed(2) + 's]';
  logLines.push(line);
  writeText(statusPath, logLines.join('\n') + '\n');
}

// Polls fn() until it returns something truthy. Errors count as "not yet" - AX queries
// against REAPER time out while Kontakt blocks the main thread loading an instrument.
function waitFor(fn, timeoutSec, intervalSec) {
  var t0 = Date.now();
  while (Date.now() - t0 < timeoutSec * 1000) {
    var r = null;
    try { r = fn(); } catch (e) { r = null; }
    if (r) return r;
    delay(intervalSec || 0.1);
  }
  return null;
}

function reaperProcess() {
  var procs = se.applicationProcesses.whose({ bundleIdentifier: 'com.cockos.reaper' })();
  if (procs.length === 0) throw new Error('REAPER process not found');
  return procs[0];
}

function findWindow(proc, match) {
  var names = proc.windows.name();
  for (var i = 0; i < names.length; i++) {
    if (names[i] && match(names[i])) return proc.windows.byName(names[i]);
  }
  return null;
}

function waitForPluginWindow(proc, job) {
  return waitFor(function () {
    return findWindow(proc, function (n) { return n === job.fxTitle; })
      || findWindow(proc, function (n) { return n.indexOf(job.fxTitle) >= 0; });
  }, job.windowTimeout || 10);
}

function raise(proc, win) {
  proc.frontmost = true;
  try { win.actions.byName('AXRaise').perform(); } catch (e) {}
  waitFor(function () { return proc.frontmost(); }, 1, 0.03);
}

// Mouse position in top-left-origin screen coords (same space as System Events / CGEvent).
function mouseTopLeft() {
  var m = $.NSEvent.mouseLocation;
  var h = $.NSScreen.screens.objectAtIndex(0).frame.size.height;
  return { x: m.x, y: h - m.y };
}

// type: 1 = left down, 2 = left up, 5 = moved. Posted at the HID tap like a real mouse.
function postMouse(type, p) {
  $.CGEventPost(0, $.CGEventCreateMouseEvent(null, type, p, 0));
}

// macOS silently drops posted events when the responsible app (REAPER) lacks the right.
function click(x, y) {
  if (!$.CGPreflightPostEventAccess()) {
    $.CGRequestPostEventAccess();
    throw new Error('Mouse events are blocked (PostEventAccess false)');
  }
  var p = { x: x, y: y };
  postMouse(5, p); delay(0.05);
  postMouse(1, p); delay(0.05);
  postMouse(2, p);
}

// Clicks Kontakt's Files button once (a second click would close the menu again).
// Kontakt draws the menu inside its own view, so there is no popup window to wait for.
function openFilesMenu(proc, win, job) {
  raise(proc, win);
  var pos = win.position();
  status('STEP click Files button (offset ' + job.clickX + ',' + job.clickY + ', window at ' + pos + ')');
  click(pos[0] + job.clickX, pos[1] + job.clickY);
}

function setFocusedText(proc, text) {
  try {
    var el = proc.attributes.byName('AXFocusedUIElement').value();
    el.value = text;
    return el.value() === text;
  } catch (e) {
    return false;
  }
}

// Fallback for setFocusedText: paste via clipboard (handles non-ASCII paths, unlike keystroke).
function pasteText(text) {
  var app = Application.currentApplication();
  app.includeStandardAdditions = true;
  var old = null;
  try { old = app.theClipboard(); } catch (e) {}
  app.setTheClipboardTo(text);
  se.keystroke('a', { using: 'command down' });
  se.keystroke('v', { using: 'command down' });
  delay(0.3);
  if (old !== null) app.setTheClipboardTo(old);
}

// ---------------------------------------------------------------- modes

function doCheck(job) {
  status('AXIsProcessTrusted ' + $.AXIsProcessTrusted());
  status('PostEventAccess ' + $.CGPreflightPostEventAccess());
  var proc = reaperProcess();
  status('WINDOWS ' + JSON.stringify(proc.windows.name()));
}

// Counts down, then returns the mouse position relative to the window's top-left.
function countdownOffset(win, label, seconds) {
  for (var s = seconds; s > 0; s--) {
    status('COUNTDOWN ' + label + ' ' + s);
    delay(1);
  }
  var m = mouseTopLeft();
  var pos = win.position();
  return { x: Math.round(m.x - pos[0]), y: Math.round(m.y - pos[1]) };
}

// Two points: the Files button, then (after we click it ourselves) the "Load..." menu item.
// File paths of the last drag (any source app). The drag pasteboard keeps them until the
// next drag starts; changeCount tells drags apart.
function doDragFiles(job) {
  var pb = $.NSPasteboard.pasteboardWithName($.NSPasteboardNameDrag);
  status('CHANGE ' + pb.changeCount);
  var urls = pb.readObjectsForClassesOptions($([$.NSURL]), $({ NSPasteboardURLReadingFileURLsOnlyKey: true }));
  if (urls.isNil()) return;
  for (var i = 0; i < urls.count; i++) status('FILE ' + urls.objectAtIndex(i).path.js);
}

function doCalibrate(job) {
  var proc = reaperProcess();
  var win = waitForPluginWindow(proc, job);
  if (!win) throw new Error('Plugin window not found: ' + job.fxTitle);

  var files = countdownOffset(win, 'Files', job.countdown || 5);
  status('OFFSET files ' + files.x + ' ' + files.y);
  job.clickX = files.x;
  job.clickY = files.y;
  openFilesMenu(proc, win, job);

  var load = countdownOffset(win, 'Load', job.countdown || 5);
  status('OFFSET load ' + load.x + ' ' + load.y);
  se.keyCode(53); // escape: close the menu again
}

function doLoad(job) {
  var proc = reaperProcess();
  var isDialog = function (n) { return n !== job.fxTitle && n.indexOf(job.dialogTitle) >= 0; };

  status('STEP wait for plugin window: ' + job.fxTitle);
  var win = waitForPluginWindow(proc, job);
  if (!win) throw new Error('Plugin window not found: ' + job.fxTitle);
  delay(job.guiDelay || 0);

  var mouse = mouseTopLeft();
  openFilesMenu(proc, win, job);
  delay(job.menuDelay || 0.1);
  if (job.loadX >= 0 && job.loadY >= 0) {
    var pos = win.position();
    status('STEP click Load... (offset ' + job.loadX + ',' + job.loadY + ')');
    click(pos[0] + job.loadX, pos[1] + job.loadY);
  } else {
    status('STEP menu keys ' + job.menuKeys);
    String(job.menuKeys || '').split(',').forEach(function (k) {
      if (k.trim() === '') return;
      se.keyCode(parseInt(k, 10));
      delay(0.1);
    });
  }
  if (job.restoreMouse) postMouse(5, mouse);

  status('STEP wait for dialog containing "' + job.dialogTitle + '"');
  var dlg = waitFor(function () { return findWindow(proc, isDialog); }, job.dialogTimeout || 10, 0.05);
  if (!dlg) throw new Error('Load dialog did not appear - run "Calibrate Kontakt clicks"');

  status('STEP go to file');
  se.keystroke('g', { using: ['command down', 'shift down'] });
  if (!waitFor(function () { return dlg.sheets().length > 0; }, 1, 0.03)) status('STEP no "Go to folder" sheet seen');
  if (!setFocusedText(proc, job.path)) {
    status('STEP setting text via AX failed, pasting instead');
    pasteText(job.path);
  }
  se.keyCode(36); // return: close "Go to folder", file gets selected

  var openButton = dlg.buttons.byName(job.openButton || 'Open');
  var ready = waitFor(function () { return dlg.sheets().length === 0 && openButton.enabled(); }, 2, 0.03);
  status('STEP open' + (ready ? '' : ' (button not seen enabled)'));
  var clicked = false;
  try {
    if (openButton.exists()) { openButton.click(); clicked = true; }
  } catch (e) {}
  if (!clicked) se.keyCode(36);

  status('STEP wait for instrument to load');
  var finished = waitFor(function () {
    var names = proc.windows.name();
    return !names.some(function (n) { return n && (isDialog(n) || n.indexOf('Progress') >= 0); });
  }, job.loadTimeout || 120, 0.1);
  if (!finished) throw new Error('Timed out waiting for the dialog/progress window to close');
}

function run(argv) {
  var mode = argv[0];
  statusPath = argv[2];
  try {
    var job = JSON.parse(readText(argv[1]) || '{}');
    if (mode === 'check') doCheck(job);
    else if (mode === 'calibrate') doCalibrate(job);
    else if (mode === 'load') doLoad(job);
    else if (mode === 'dragfiles') doDragFiles(job);
    else throw new Error('Unknown mode: ' + mode);
    status('DONE');
  } catch (e) {
    status('ERROR: ' + e.message + (e.errorNumber ? ' (' + e.errorNumber + ')' : ''));
  }
}
