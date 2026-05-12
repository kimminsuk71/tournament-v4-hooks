const cfg = window.TOURNAMENT_BOARD;
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
  }).format(value);
}

function flagUrl(code) {
  return `https://flagcdn.com/w80/${encodeURIComponent(code)}.png`;
}

function renderHub() {
  document.getElementById("hubBurned").textContent = `${compact(cfg.hub.totalBurned)} ${cfg.hub.symbol}`;
  document.getElementById("pendingBuyback").textContent = usd(cfg.hub.pendingBuybackUsd);
  document.getElementById("treasuryRouted").textContent = usd(cfg.hub.treasuryRoutedUsd);
}

function renderTeams() {
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
              <div><dt>Buyback</dt><dd>${usd(team.buyback)}</dd></div>
            </dl>
            <div class="pool">Pool ${team.pool}</div>
          </div>
        </article>
      `
    )
    .join("");

  document.getElementById("updatedAt").textContent = `Updated ${new Date().toLocaleTimeString()}`;
}

function renderMatches() {
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

sortMode.addEventListener("change", renderTeams);
searchBox.addEventListener("input", renderTeams);

renderHub();
renderTeams();
renderMatches();
