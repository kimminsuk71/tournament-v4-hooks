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
  return `https://flagcdn.com/w80/${encodeURIComponent(code)}.png`;
}

function displayTokenAmount(value) {
  const numeric = Number(value ?? 0);
  return Number.isFinite(numeric) ? compact(numeric) : "0";
}

function normalizeBoard(raw) {
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
    teams
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

  grid.innerHTML = teams
    .map(
      (team, index) => `
        <article class="team-card">
          <div class="rank">${index + 1}</div>
          <img class="flag" src="${flagUrl(team.countryCode)}" alt="" loading="lazy" />
          <div class="team-main">
            <div class="team-title">
              <h3>${team.name}</h3>
              <span>${team.symbol}</span>
            </div>
            <dl class="stats">
              <div><dt>Market cap</dt><dd>${usd(team.marketCap)}</dd></div>
              <div><dt>24h volume</dt><dd>${usd(team.volume)}</dd></div>
              <div><dt>Buyback</dt><dd>${displayTokenAmount(team.buyback)}</dd></div>
            </dl>
            <div class="pool">Pool ${team.pool}</div>
          </div>
        </article>
      `
    )
    .join("");

  document.getElementById("updatedAt").textContent = `Updated ${new Date().toLocaleTimeString()}`;
}

function renderMatches(cfg) {
  matchList.innerHTML = cfg.matches
    .map(
      (match) => `
        <article class="match-card">
          <div>
            <p>${match.venue}</p>
            <h3>${match.home} vs ${match.away}</h3>
          </div>
          <time datetime="${match.date}">${new Date(`${match.date}T12:00:00`).toLocaleDateString()}</time>
        </article>
      `
    )
    .join("");
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
