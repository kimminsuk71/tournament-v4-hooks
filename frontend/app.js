const grid = document.getElementById("teamGrid");
const matchList = document.getElementById("matchList");
const sortMode = document.getElementById("sortMode");
const searchBox = document.getElementById("searchBox");

function usd(value) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0
  }).format(value);
}

function compact(value) {
  return new Intl.NumberFormat("en-US", {
    notation: "compact",
    maximumFractionDigits: 2
  }).format(Number(value ?? 0));
}

function flagUrl(code) {
  const normalized = String(code ?? "").toLowerCase();
  return `https://flagcdn.com/w80/${encodeURIComponent(normalized)}.png`;
}

function displayTokenAmount(value) {
  const numeric = Number(value ?? 0);
  return Number.isFinite(numeric) ? compact(numeric) : "0";
}

function normalizeBoard(raw) {
  raw ??= {};
  const hub = raw.hub ?? {};
  const teams = (raw.teams ?? []).map((team) => {
    const buyback = Number(team.buyback ?? team.buybackDisplay ?? 0);
    const treasury = Number(team.treasury ?? team.treasuryDisplay ?? 0);
    return {
      ...team,
      buyback,
      treasury,
      pool: team.pool ?? team.poolId ?? "unregistered",
      burn: buyback,
      volume: Number(team.volume ?? 0),
      marketCap: Number(team.marketCap ?? 0)
    };
  });

  return {
    ...raw,
    hub: {
      ...hub,
      symbol: hub.symbol ?? "HUB",
      totalBurned: hub.totalBurned ?? hub.totalBurnedDisplay ?? 0,
      pendingBuyback: hub.pendingBuyback ?? hub.pendingBuybackDisplay ?? hub.pendingBuybackUsd ?? 0,
      treasuryRouted: hub.treasuryRouted ?? hub.treasuryRoutedDisplay ?? hub.treasuryRoutedUsd ?? 0
    },
    teams,
    matches: raw.matches ?? []
  };
}

async function loadBoard() {
  try {
    const response = await fetch("./generated/board-data.json", { cache: "no-store" });
    if (response.ok) return normalizeBoard(await response.json());
  } catch {
    // Opening index.html directly cannot fetch local generated JSON; config.js is the fallback.
  }
  return normalizeBoard(window.TOURNAMENT_BOARD);
}

function renderHub(cfg) {
  document.getElementById("hubBurned").textContent = `${displayTokenAmount(cfg.hub.totalBurned)} ${cfg.hub.symbol}`;
  document.getElementById("pendingBuyback").textContent = displayTokenAmount(cfg.hub.pendingBuyback);
  document.getElementById("treasuryRouted").textContent = displayTokenAmount(cfg.hub.treasuryRouted);
}

function renderTeams(cfg) {
  const mode = sortMode.value;
  const query = searchBox.value.trim().toLowerCase();
  const teams = cfg.teams
    .filter((team) => `${team.name} ${team.symbol}`.toLowerCase().includes(query))
    .sort((a, b) => b[mode] - a[mode]);

  grid.replaceChildren(...teams.map((team, index) => createTeamCard(team, index)));

  document.getElementById("updatedAt").textContent = `Updated ${new Date().toLocaleTimeString()}`;
}

function renderMatches(cfg) {
  matchList.replaceChildren(...cfg.matches.map(createMatchCard));
}

function createTeamCard(team, index) {
  const card = document.createElement("article");
  card.className = "team-card";

  const rank = document.createElement("div");
  rank.className = "rank";
  rank.textContent = String(index + 1);

  const flag = document.createElement("img");
  flag.className = "flag";
  flag.src = flagUrl(team.countryCode);
  flag.alt = "";
  flag.loading = "lazy";

  const main = document.createElement("div");
  main.className = "team-main";

  const title = document.createElement("div");
  title.className = "team-title";
  const name = document.createElement("h3");
  name.textContent = team.name;
  const symbol = document.createElement("span");
  symbol.textContent = team.symbol;
  title.append(name, symbol);

  const stats = document.createElement("dl");
  stats.className = "stats";
  stats.append(
    statItem("Market cap", usd(team.marketCap)),
    statItem("24h volume", usd(team.volume)),
    statItem("Buyback", displayTokenAmount(team.buyback))
  );

  const pool = document.createElement("div");
  pool.className = "pool";
  pool.textContent = `Pool ${team.pool}`;

  main.append(title, stats, pool);
  card.append(rank, flag, main);
  return card;
}

function statItem(label, value) {
  const wrapper = document.createElement("div");
  const term = document.createElement("dt");
  term.textContent = label;
  const description = document.createElement("dd");
  description.textContent = value;
  wrapper.append(term, description);
  return wrapper;
}

function createMatchCard(match) {
  const card = document.createElement("article");
  card.className = "match-card";

  const content = document.createElement("div");
  const venue = document.createElement("p");
  venue.textContent = match.venue;
  const title = document.createElement("h3");
  title.textContent = `${match.home} vs ${match.away}`;
  content.append(venue, title);

  const time = document.createElement("time");
  time.dateTime = match.date;
  time.textContent = new Date(`${match.date}T12:00:00`).toLocaleDateString();

  card.append(content, time);
  return card;
}

async function boot() {
  const cfg = await loadBoard();
  sortMode.addEventListener("change", () => renderTeams(cfg));
  searchBox.addEventListener("input", () => renderTeams(cfg));

  renderHub(cfg);
  renderTeams(cfg);
  renderMatches(cfg);
}

boot();
