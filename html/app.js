const state = {
  reports: [],
  filtered: [],
  selectedBundleId: ""
};

const els = {
  appPage: document.querySelector("#appPage"),
  reportPage: document.querySelector("#reportPage"),
  pageTitle: document.querySelector("#pageTitle"),
  pageSubtitle: document.querySelector("#pageSubtitle"),
  appGrid: document.querySelector("#appGrid"),
  appSearch: document.querySelector("#appSearchInput"),
  rows: document.querySelector("#reportRows"),
  detail: document.querySelector("#detail"),
  stats: document.querySelector("#stats"),
  search: document.querySelector("#searchInput"),
  level: document.querySelector("#levelFilter"),
  reload: document.querySelector("#reloadButton"),
  back: document.querySelector("#backButton")
};

async function loadReports() {
  els.appGrid.innerHTML = `<div class="empty">加载中...</div>`;
  try {
    const cacheKey = Date.now();
    const index = await fetch(`./index.json?v=${cacheKey}`, { cache: "no-store" }).then(response => response.json());
    const reports = await loadReportFiles(index.reports || []);
    state.reports = reports.sort((a, b) => String(b.time).localeCompare(String(a.time)));
    const hashBundle = new URLSearchParams(location.hash.replace(/^#/, "")).get("app");
    if (hashBundle && state.reports.some(report => report.app?.bundleId === hashBundle)) {
      selectApp(hashBundle, false);
    } else {
      showAppPage();
    }
  } catch (error) {
    state.reports = [];
    state.filtered = [];
    showAppPage();
    els.appGrid.innerHTML = `<div class="empty">未读取到 index.json，请确认文件已经上传到服务器指定目录。<br>${safe(error.message || error)}</div>`;
  }
}

async function loadReportFiles(items) {
  const results = await Promise.all(items.map(async item => {
    try {
      const response = await fetch(`./${item.path}?v=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}`);
      }
      const report = await response.json();
      return { ok: true, report: { ...report, path: item.path } };
    } catch (error) {
      return {
        ok: false,
        report: makeFallbackReport(item, error)
      };
    }
  }));
  return results.map(result => result.report);
}

function makeFallbackReport(item, error) {
  return {
    id: item.id || item.path || String(Date.now()),
    event: item.event || "report_load_failed",
    level: item.level || "warning",
    time: item.time || "",
    app: {
      bundleId: item.bundleId || "unknown",
      name: item.appName || "未知 App",
      version: item.version || "-",
      build: item.build || "-"
    },
    device: {
      model: "未知",
      systemName: "",
      systemVersion: "",
      language: "",
      region: "",
      timeZone: ""
    },
    runtime: {
      cpu: 0,
      memoryMB: 0,
      fps: 0,
      averageFPS: 0,
      minimumFPS: 0,
      launchTime: 0
    },
    network: {
      type: "unknown",
      isExpensive: false,
      isConstrained: false
    },
    disk: {
      totalGB: 0,
      freeGB: 0,
      usedGB: 0
    },
    battery: {
      level: -1,
      charging: false,
      state: "unknown",
      lowPowerMode: false
    },
    thermal: {
      state: "unknown"
    },
    page: {
      current: "报告文件读取失败",
      previous: "",
      stayDuration: 0
    },
    counters: {
      socketReconnects: 0,
      uploadFailures: 0,
      apiFailures: 0
    },
    eventHistory: [],
    networkHistory: [],
    path: item.path,
    loadError: String(error?.message || error || "")
  };
}

function showAppPage() {
  state.selectedBundleId = "";
  location.hash = "";
  els.pageTitle.textContent = "ZWB Monitor";
  els.pageSubtitle.textContent = "应用性能监控总览";
  els.appPage.classList.remove("hidden");
  els.reportPage.classList.add("hidden");
  els.detail.classList.add("hidden");
  els.back.classList.add("hidden");
  renderHomeStats();
  renderAppCards();
}

function selectApp(bundleId, updateHash = true) {
  state.selectedBundleId = bundleId;
  const app = appSummaries().find(item => item.bundleId === bundleId);
  if (updateHash) {
    location.hash = `app=${encodeURIComponent(bundleId)}`;
  }
  els.pageTitle.textContent = app?.name || "应用报告";
  els.pageSubtitle.textContent = `${bundleId} 的性能预警报告`;
  els.appPage.classList.add("hidden");
  els.reportPage.classList.remove("hidden");
  els.detail.classList.remove("hidden");
  els.back.classList.remove("hidden");
  applyFilters();
}

function appSummaries() {
  const groups = new Map();
  state.reports.forEach(report => {
    const bundleId = report.app?.bundleId || "unknown";
    if (!groups.has(bundleId)) {
      groups.set(bundleId, {
        bundleId,
        name: report.app?.name || "未知 App",
        versions: new Set(),
        reports: [],
        devices: new Set(),
        pages: new Set()
      });
    }
    const group = groups.get(bundleId);
    group.reports.push(report);
    if (report.app?.version) group.versions.add(report.app.version);
    if (report.device?.model) group.devices.add(report.device.model);
    if (report.page?.current) group.pages.add(report.page.current);
  });

  return [...groups.values()].map(group => {
    const latest = group.reports[0];
    return {
      ...group,
      total: group.reports.length,
      warning: group.reports.filter(report => report.level === "warning").length,
      critical: group.reports.filter(report => report.level === "critical").length,
      latest
    };
  }).sort((a, b) => {
    if (b.critical !== a.critical) return b.critical - a.critical;
    return String(b.latest?.time || "").localeCompare(String(a.latest?.time || ""));
  });
}

function renderHomeStats() {
  const total = state.reports.length;
  const critical = state.reports.filter(report => report.level === "critical").length;
  const warning = state.reports.filter(report => report.level === "warning").length;
  const apps = appSummaries().length;
  els.stats.innerHTML = [
    ["接入 App", apps],
    ["全部报告", total],
    ["严重告警", critical],
    ["警告告警", warning]
  ].map(([label, value]) => `<div class="stat"><strong>${value}</strong><span>${label}</span></div>`).join("");
}

function renderAppCards() {
  const keyword = els.appSearch.value.trim().toLowerCase();
  const apps = appSummaries().filter(app => {
    const text = [app.name, app.bundleId, [...app.versions].join(" ")].join(" ").toLowerCase();
    return !keyword || text.includes(keyword);
  });

  if (!apps.length) {
    els.appGrid.innerHTML = `<div class="empty">暂无匹配的 App</div>`;
    return;
  }

  els.appGrid.innerHTML = apps.map(app => `
    <button class="app-card" type="button" data-bundle="${safe(app.bundleId)}">
      <div class="app-card-head">
        <div>
          <strong>${safe(app.name)}</strong>
          <span>${safe(app.bundleId)}</span>
        </div>
        <em class="${app.critical > 0 ? "critical" : app.warning > 0 ? "warning" : "info"}">${app.critical > 0 ? "严重" : app.warning > 0 ? "警告" : "正常"}</em>
      </div>
      <div class="app-metrics">
        <div><b>${app.total}</b><span>报告</span></div>
        <div><b>${app.critical}</b><span>严重</span></div>
        <div><b>${app.warning}</b><span>警告</span></div>
        <div><b>${app.devices.size}</b><span>设备</span></div>
      </div>
      <div class="app-card-foot">
        <span>版本：${safe([...app.versions].join(" / ") || "-")}</span>
        <span>最近：${safe(displayEvent(app.latest?.event))}</span>
      </div>
    </button>
  `).join("");

  [...els.appGrid.querySelectorAll(".app-card")].forEach(card => {
    card.addEventListener("click", () => selectApp(card.dataset.bundle));
  });
}

function applyFilters() {
  const keyword = els.search.value.trim().toLowerCase();
  const level = els.level.value;
  state.filtered = state.reports.filter(report => {
    const text = [
      report.app?.name,
      report.app?.bundleId,
      displayEvent(report.event),
      report.event,
      report.device?.model,
      report.page?.current
    ].join(" ").toLowerCase();
    return report.app?.bundleId === state.selectedBundleId
      && (!keyword || text.includes(keyword))
      && (!level || report.level === level);
  });
  renderReportStats();
  renderRows();
}

function renderReportStats() {
  const selected = state.reports.filter(report => report.app?.bundleId === state.selectedBundleId);
  const critical = selected.filter(report => report.level === "critical").length;
  const warning = selected.filter(report => report.level === "warning").length;
  const pages = new Set(selected.map(report => report.page?.current).filter(Boolean)).size;
  els.stats.innerHTML = [
    ["报告", selected.length],
    ["严重", critical],
    ["警告", warning],
    ["页面", pages]
  ].map(([label, value]) => `<div class="stat"><strong>${value}</strong><span>${label}</span></div>`).join("");
}

function renderRows() {
  if (!state.filtered.length) {
    els.rows.innerHTML = `<tr><td colspan="9">暂无匹配报告</td></tr>`;
    els.detail.innerHTML = "";
    return;
  }
  els.rows.innerHTML = state.filtered.map((report, index) => `
    <tr data-index="${index}">
      <td>${safe(report.time)}</td>
      <td>${safe(report.app?.name)} ${safe(report.app?.version)}</td>
      <td><span class="badge ${safe(report.level)}">${safe(displayEvent(report.event))}</span></td>
      <td>${safe(report.page?.current || "未知")}</td>
      <td>${number(report.runtime?.cpu)}%</td>
      <td>${number(report.runtime?.memoryMB)} MB</td>
      <td>${safe(report.runtime?.fps ?? "-")}</td>
      <td>${safe(report.device?.model)}</td>
      <td>${safe(displayNetwork(report.network?.type))}</td>
    </tr>
  `).join("");

  [...els.rows.querySelectorAll("tr")].forEach(row => {
    row.addEventListener("click", () => renderDetail(state.filtered[Number(row.dataset.index)]));
  });
  renderDetail(state.filtered[0]);
}

function renderDetail(report) {
  if (!report) {
    els.detail.innerHTML = "";
    return;
  }
  els.detail.innerHTML = `
    <h2>${safe(displayEvent(report.event))}</h2>
    <div class="detail-grid">
      <div><span>App</span><strong>${safe(report.app?.name)} ${safe(report.app?.version)}(${safe(report.app?.build)})</strong></div>
      <div><span>Bundle ID</span><strong>${safe(report.app?.bundleId)}</strong></div>
      <div><span>告警等级</span><strong>${safe(displayLevel(report.level))}</strong></div>
      <div><span>设备</span><strong>${safe(report.device?.model)} / ${safe(report.device?.systemVersion)}</strong></div>
      <div><span>页面</span><strong>${safe(report.page?.current || "未知")}</strong></div>
      <div><span>电量</span><strong>${safe(report.battery?.level)}% ${safe(displayBattery(report.battery?.state))}</strong></div>
      <div><span>温度</span><strong>${safe(displayThermal(report.thermal?.state))}</strong></div>
      <div><span>网络</span><strong>${safe(displayNetwork(report.network?.type))}</strong></div>
      <div><span>磁盘剩余</span><strong>${number(report.disk?.freeGB)} GB</strong></div>
      <div><span>CPU</span><strong>${number(report.runtime?.cpu)}%</strong></div>
      <div><span>内存</span><strong>${number(report.runtime?.memoryMB)} MB</strong></div>
      <div><span>报告路径</span><strong>${safe(report.path || "")}</strong></div>
    </div>
    <pre>${safe(readableReport(report))}</pre>
  `;
}

function readableReport(report) {
  const lines = [
    "【基础信息】",
    `报告 ID：${report.id || ""}`,
    `触发事件：${displayEvent(report.event)}`,
    `告警等级：${displayLevel(report.level)}`,
    `采集时间：${report.time || ""}`,
    "",
    "【App 信息】",
    `App 名称：${report.app?.name || ""}`,
    `Bundle ID：${report.app?.bundleId || ""}`,
    `版本号：${report.app?.version || ""}`,
    `Build：${report.app?.build || ""}`,
    "",
    "【设备信息】",
    `设备型号：${report.device?.model || ""}`,
    `系统版本：${report.device?.systemName || ""} ${report.device?.systemVersion || ""}`,
    `语言：${report.device?.language || ""}`,
    `地区：${report.device?.region || ""}`,
    `时区：${report.device?.timeZone || ""}`,
    "",
    "【运行状态】",
    `CPU 占用：${number(report.runtime?.cpu)}%`,
    `内存占用：${number(report.runtime?.memoryMB)} MB`,
    `当前 FPS：${report.runtime?.fps ?? "-"}`,
    `平均 FPS：${report.runtime?.averageFPS ?? "-"}`,
    `最低 FPS：${report.runtime?.minimumFPS ?? "-"}`,
    "",
    "【网络 / 存储】",
    `网络类型：${displayNetwork(report.network?.type)}`,
    `低数据模式：${report.network?.isConstrained ? "是" : "否"}`,
    `昂贵网络：${report.network?.isExpensive ? "是" : "否"}`,
    `磁盘总空间：${number(report.disk?.totalGB)} GB`,
    `磁盘剩余：${number(report.disk?.freeGB)} GB`,
    `磁盘已用：${number(report.disk?.usedGB)} GB`,
    "",
    "【电量 / 温度】",
    `电量：${report.battery?.level ?? "-"}%`,
    `充电状态：${displayBattery(report.battery?.state)}`,
    `是否充电：${report.battery?.charging ? "是" : "否"}`,
    `低电量模式：${report.battery?.lowPowerMode ? "是" : "否"}`,
    `温度状态：${displayThermal(report.thermal?.state)}`,
    "",
    "【页面】",
    `当前页面：${report.page?.current || "未知"}`,
    `上一个页面：${report.page?.previous || "未知"}`,
    `停留时长：${number(report.page?.stayDuration)} 秒`,
    "",
    "【计数器】",
    `Socket 重连次数：${report.counters?.socketReconnects ?? 0}`,
    `上传失败次数：${report.counters?.uploadFailures ?? 0}`,
    `API 失败次数：${report.counters?.apiFailures ?? 0}`
  ];
  return lines.join("\n");
}

function displayEvent(event) {
  return ({
    manual: "手动采集",
    demo_button: "Demo 按钮采集",
    sample: "定时采样",
    high_memory: "内存过高",
    high_cpu: "CPU 过高",
    low_fps: "FPS 过低",
    thermal_serious: "设备温度严重",
    thermal_critical: "设备温度危险",
    low_disk: "磁盘空间不足",
    socket_reconnect: "Socket 重连过多",
    upload_failure: "上传失败过多",
    api_failure: "API 失败过多",
    ZWBMonitorStarted: "监控已启动",
    PageAppear: "页面展示",
    DemoButtonTapped: "Demo 按钮点击",
    report_load_failed: "报告文件读取失败"
  })[event] || event || "未知事件";
}

function displayLevel(level) {
  return ({
    info: "普通信息",
    warning: "警告",
    critical: "严重"
  })[level] || level || "未知";
}

function displayNetwork(network) {
  return ({
    WiFi: "无线网络",
    Cellular: "蜂窝网络",
    Ethernet: "有线网络",
    Other: "其他网络",
    Offline: "无网络",
    unknown: "未知",
    disabled: "未开启监控"
  })[network] || network || "未知";
}

function displayBattery(state) {
  return ({
    charging: "充电中",
    full: "已充满",
    unplugged: "未充电",
    unknown: "未知",
    disabled: "未开启监控"
  })[state] || state || "未知";
}

function displayThermal(state) {
  return ({
    nominal: "正常",
    fair: "偏热",
    serious: "严重发热",
    critical: "危险发热",
    unknown: "未知",
    disabled: "未开启监控"
  })[state] || state || "未知";
}

function number(value) {
  return typeof value === "number" ? value.toFixed(value % 1 === 0 ? 0 : 2) : "-";
}

function safe(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;"
  }[char]));
}

els.appSearch.addEventListener("input", renderAppCards);
els.search.addEventListener("input", applyFilters);
els.level.addEventListener("change", applyFilters);
els.reload.addEventListener("click", loadReports);
els.back.addEventListener("click", showAppPage);
window.addEventListener("hashchange", () => {
  const hashBundle = new URLSearchParams(location.hash.replace(/^#/, "")).get("app");
  if (hashBundle) {
    selectApp(hashBundle, false);
  } else {
    showAppPage();
  }
});

loadReports();
