// Variables used by Scriptable.
// icon-color: deep-green; icon-glyph: signal;

const summaryURL = "https://codexradar.com/data/codex-four-task-summary.json";
const refreshInterval = 2 * 60 * 60 * 1000;
const retryInterval = 30 * 60 * 1000;
const files = FileManager.local();
const cachePath = files.joinPath(files.cacheDirectory(), "codex-radar-top-four.json");
const scorePattern = /^\d+(?:\.\d+)?$/;

const headerLayout = {
  top: 9,
  height: 18,
  inset: 22,
  gapToTiles: 5,
  titleWidth: 96,
  timeWidth: 70,
};

const dateFormatter = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Asia/Shanghai",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

const palette = {
  case: new Color("#111917"),
  title: new Color("#E9F0E8"),
  date: new Color("#BDD0C1"),
  ink: new Color("#14251C"),
  secondaryInk: new Color("#2D4437"),
  inactiveSegment: new Color("#253A2C", 0.11),
};

const digitSegments = ["abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"];
const segmentPolygons = {
  a: horizontalSegment(0),
  b: verticalSegment(9.5, 1.7),
  c: verticalSegment(9.5, 11.7),
  d: horizontalSegment(19.1),
  e: verticalSegment(0, 11.7),
  f: verticalSegment(0, 1.7),
  g: horizontalSegment(9.55),
};

const { snapshot, refreshDelay } = await loadRanking();
const widget = buildWidget(snapshot);

if (config.runsInWidget) {
  widget.refreshAfterDate = new Date(Date.now() + refreshDelay);
  widget.url = URLScheme.forRunningScript();
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();

async function loadRanking() {
  let snapshot;
  try {
    const request = new Request(summaryURL);
    request.headers = { Accept: "application/json" };
    request.timeoutInterval = 10;
    const summary = await request.loadJSON();
    if (request.response.statusCode !== 200) {
      throw new Error(`Codex Radar HTTP ${request.response.statusCode}`);
    }
    snapshot = {
      leaders: topModels(summary.rows),
      fetchedAt: new Date().toISOString(),
    };
  } catch (error) {
    console.log(String(error));
    return { snapshot: readCache(), refreshDelay: retryInterval };
  }

  try {
    files.writeString(cachePath, JSON.stringify(snapshot));
  } catch (error) {
    console.log(String(error));
  }
  return { snapshot, refreshDelay: refreshInterval };
}

function readCache() {
  try {
    if (!files.fileExists(cachePath)) return null;
    const snapshot = JSON.parse(files.readString(cachePath));
    const leaders = snapshot?.leaders;
    if (!Array.isArray(leaders) || leaders.length < 1 || leaders.length > 4 || !formatDate(snapshot.fetchedAt)) {
      return null;
    }
    const valid = leaders.every(leader => leader
      && [leader.model, leader.effort, leader.score, leader.cost].every(value => typeof value === "string" && value.trim().length > 0)
      && scorePattern.test(leader.score));
    return valid ? snapshot : null;
  } catch (error) {
    console.log(String(error));
    return null;
  }
}

function topModels(rows) {
  if (!Array.isArray(rows)) throw new Error("榜单缺少成绩列表");

  // 用原始分数排序。同分时保留官网的模型和档位出现顺序。
  const bestByModel = new Map();
  for (const row of rows) {
    if (typeof row?.model !== "string" || !row.model) continue;
    if (!bestByModel.has(row.model)) bestByModel.set(row.model, null);
    if (!Number.isFinite(row.score150) || typeof row.effort !== "string" || !row.effort) continue;
    const best = bestByModel.get(row.model);
    if (!best || row.score150 > best.score150) bestByModel.set(row.model, row);
  }

  const leaders = Array.from(bestByModel.values()).filter(Boolean)
    .sort((a, b) => b.score150 - a.score150)
    .slice(0, 4)
    .map(row => ({
      model: modelName(row.model),
      effort: row.effort,
      score: scorePattern.test(row.score_display) ? String(row.score_display) : row.score150.toFixed(2),
      cost: formatCost(row.cost_usd),
    }));
  if (leaders.length === 0) throw new Error("榜单暂无有效成绩");
  return leaders;
}

function modelName(model) {
  const gpt = /^gpt-([\d.]+)-(.+)$/i.exec(model);
  if (!gpt) return model;
  const name = gpt[2].split("-").map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
  return `GPT-${gpt[1]} ${name}`;
}

function formatCost(cost) {
  if (!Number.isFinite(cost) || cost < 0) return "—";
  return `$${cost >= 0.1 ? cost.toFixed(2) : Number(cost.toPrecision(2))}`;
}

function formatDate(value) {
  if (typeof value !== "string" || !value) return "";
  const date = new Date(value.replace(/(\.\d{3})\d+(?=[Z+-])/, "$1"));
  if (!Number.isFinite(date.getTime())) return "";
  const parts = Object.fromEntries(dateFormatter.formatToParts(date).map(part => [part.type, part.value]));
  return `${parts.month}/${parts.day} ${parts.hour}:${parts.minute}`;
}

function buildWidget(snapshot) {
  const screen = Device.screenSize();
  const compact = Math.min(screen.width, screen.height) < 428;
  const wide = Math.min(screen.width, screen.height) >= 440;
  const tileWidth = wide ? 173 : compact ? 144 : 167;
  const tileHeight = compact ? 54 : 62;
  const view = new ListWidget();
  view.backgroundColor = palette.case;
  view.setPadding(headerLayout.top, 0, 0, 0);

  const header = view.addStack();
  header.centerAlignContent();
  header.addSpacer(headerLayout.inset);
  const title = header.addImage(drawWordmark());
  title.imageSize = new Size(headerLayout.titleWidth, headerLayout.height);
  header.addSpacer();

  const clock = header.addStack();
  clock.size = new Size(headerLayout.timeWidth, headerLayout.height);
  clock.centerAlignContent();
  clock.addSpacer();
  const fetched = formatDate(snapshot?.fetchedAt);
  if (fetched) addText(clock, fetched, Font.mediumMonospacedSystemFont(10), palette.date);
  header.addSpacer(headerLayout.inset);
  view.addSpacer(headerLayout.gapToTiles);

  if (!snapshot) {
    view.addSpacer();
    addText(view, "暂时取不到榜单", Font.semiboldSystemFont(14), palette.title).centerAlignText();
    view.addSpacer(4);
    addText(view, "点按重试", Font.systemFont(11), palette.date).centerAlignText();
    view.addSpacer();
    return view;
  }

  const leadingPanel = drawPanel(tileWidth, tileHeight, true);
  const panel = drawPanel(tileWidth, tileHeight, false);
  for (let index = 0; index < 4; index += 2) {
    const row = view.addStack();
    row.addSpacer();
    addTile(row, snapshot.leaders[index], index === 0 ? leadingPanel : panel, tileWidth, tileHeight, compact);
    row.addSpacer(8);
    addTile(row, snapshot.leaders[index + 1], panel, tileWidth, tileHeight, compact);
    row.addSpacer();
    if (index === 0) view.addSpacer(6);
  }
  view.addSpacer();
  return view;
}

function drawWordmark() {
  // 方形分段字形，使用独立线段保留每个切口。
  const glyphs = {
    C: { width: 11, lines: [[[2.4, 1], [10, 1]], [[1, 2.5], [1, 11.5]], [[2.4, 13], [10, 13]]] },
    o: { width: 9, lines: [[[2.3, 5], [6.7, 5]], [[8, 6.4], [8, 11.6]], [[6.7, 13], [2.3, 13]], [[1, 11.6], [1, 6.4]]] },
    d: { width: 9, lines: [[[2.4, 5], [6.6, 5]], [[8, 1], [8, 12]], [[6.6, 13], [2.4, 13]], [[1, 11.6], [1, 6.4]]] },
    e: { width: 9, lines: [[[2.4, 5], [6.6, 5]], [[8, 6.4], [8, 8.7]], [[6.7, 9], [2.3, 9]], [[1, 6.4], [1, 11.6]], [[2.3, 13], [7.8, 13]]] },
    x: { width: 9, lines: [[[1, 5], [3.5, 7.9]], [[5.5, 10.1], [8, 13]], [[8, 5], [5.5, 7.9]], [[3.5, 10.1], [1, 13]]] },
    R: { width: 11, lines: [[[2.4, 1], [8.6, 1]], [[10, 2.5], [10, 6.5]], [[8.6, 8], [2.4, 8]], [[1, 2.5], [1, 13]], [[5.8, 9.5], [10, 13]]] },
    a: { width: 9, lines: [[[1.9, 5], [6.7, 5]], [[8, 6.4], [8, 12]], [[6.7, 13], [2.3, 13]], [[1, 11.6], [1, 10.3]], [[2.3, 9], [6.7, 9]]] },
    r: { width: 7, lines: [[[1, 5.9], [1, 13]], [[2.4, 5], [6.1, 5]]] },
  };
  const scale = 0.82;
  const yOffset = (headerLayout.height - 16 * scale) / 2;
  const path = new Path();
  let xOffset = 1;
  for (const character of "Codex Radar") {
    if (character === " ") {
      xOffset += 6.4;
      continue;
    }
    const glyph = glyphs[character];
    for (const [[x1, y1], [x2, y2]] of glyph.lines) {
      path.move(new Point((xOffset + x1) * scale, yOffset + (1 + y1) * scale));
      path.addLine(new Point((xOffset + x2) * scale, yOffset + (1 + y2) * scale));
    }
    xOffset += glyph.width + 1.45;
  }

  const context = new DrawContext();
  context.size = new Size(headerLayout.titleWidth, headerLayout.height);
  context.opaque = false;
  context.respectScreenScale = true;
  context.setStrokeColor(new Color("#DCEADD"));
  context.setLineWidth(1.85 * scale);
  context.addPath(path);
  context.strokePath();
  return context.getImage();
}

function addTile(row, leader, background, width, height, compact) {
  const tile = row.addStack();
  tile.layoutVertically();
  tile.size = new Size(width, height);
  tile.setPadding(7, 9, 7, 9);
  tile.backgroundImage = background;
  tile.cornerRadius = 9;
  if (!leader) {
    tile.addSpacer();
    addText(tile, "—", Font.mediumMonospacedSystemFont(13), palette.secondaryInk).centerAlignText();
    tile.addSpacer();
    return;
  }

  const labelRow = tile.addStack();
  labelRow.centerAlignContent();
  addText(labelRow, leader.model, Font.semiboldSystemFont(compact ? 10 : 12), palette.ink);
  labelRow.addSpacer(4);
  labelRow.addSpacer();
  addText(labelRow, leader.effort, Font.mediumMonospacedSystemFont(9), palette.secondaryInk);

  tile.addSpacer(compact ? 4 : 6);
  const values = tile.addStack();
  values.bottomAlignContent();
  const score = drawScore(leader.score, compact ? 0.8 : 1);
  const display = values.addImage(score.image);
  display.imageSize = score.size;
  values.addSpacer(3);
  addText(values, "/150", Font.mediumMonospacedSystemFont(8), palette.secondaryInk);
  values.addSpacer(4);
  values.addSpacer();
  addText(values, leader.cost, Font.semiboldMonospacedSystemFont(compact ? 10 : 12), palette.ink);
}

function addText(stack, value, font, color) {
  const label = stack.addText(value);
  label.font = font;
  label.textColor = color;
  label.lineLimit = 1;
  label.minimumScaleFactor = 0.7;
  return label;
}

function drawPanel(width, height, leading) {
  const context = new DrawContext();
  context.size = new Size(width, height);
  context.opaque = false;
  context.respectScreenScale = true;

  // 外框、压边和玻璃内壁依次缩进，形成液晶面板的厚度。
  const layers = [
    [0, "#53665C"],
    [0.9, leading ? "#D3E4B7" : "#C4D4CA"],
    [2.2, "#4D6155"],
    [3.4, leading ? "#B1C498" : "#9FB4A6"],
  ];
  for (const [inset, color] of layers) {
    const path = new Path();
    const radius = 9 - inset;
    path.addRoundedRect(new Rect(inset, inset, width - 2 * inset, height - 2 * inset), radius, radius);
    context.setFillColor(new Color(color));
    context.addPath(path);
    context.fillPath();
  }

  context.setFillColor(new Color("#30463A", 0.06));
  for (let y = 8; y < height - 7; y += 2) {
    context.fillRect(new Rect(6, y, width - 12, 0.35));
  }
  return context.getImage();
}

function horizontalSegment(y) {
  return [[2, y], [9.2, y], [10.4, y + 1.2], [9.2, y + 2.4], [2, y + 2.4], [0.8, y + 1.2]];
}

function verticalSegment(x, y) {
  return [[x, y + 1.2], [x + 1.2, y], [x + 2.4, y + 1.2], [x + 2.4, y + 6.2], [x + 1.2, y + 7.4], [x, y + 6.2]];
}

function drawScore(score, scale) {
  const characters = String(score).split("");
  const advances = characters.map(character => character === "." ? 5.5 : 14);
  const width = advances.reduce((sum, advance) => sum + advance, 0);
  const size = new Size(Math.ceil(width * scale), Math.ceil(22 * scale));
  const context = new DrawContext();
  context.size = size;
  context.opaque = false;
  context.respectScreenScale = true;

  let offset = 0;
  for (const [index, digit] of characters.entries()) {
    if (digit === ".") {
      context.setFillColor(palette.ink);
      context.fillRect(new Rect(offset * scale, 19 * scale, 2.3 * scale, 2.3 * scale));
    } else {
      const active = digitSegments[Number(digit)] || "";
      for (const [name, points] of Object.entries(segmentPolygons)) {
        const path = new Path();
        path.addLines(points.map(([x, y]) => new Point((offset + x) * scale, y * scale)));
        path.closeSubpath();
        context.setFillColor(active.includes(name) ? palette.ink : palette.inactiveSegment);
        context.addPath(path);
        context.fillPath();
      }
    }
    offset += advances[index];
  }
  return { image: context.getImage(), size };
}
