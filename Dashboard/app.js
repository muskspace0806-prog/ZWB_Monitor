const state = {
  reports: [],
  filtered: []
};

const els = {
  rows: document.querySelector("#reportRows"),
  detail: document.querySelector("#detail"),
  stats: document.querySelector("#stats"),
  search: document.querySelector("#searchInput"),
  level: document.querySelector("#levelFilter"),
  reload: document.querySelector("#reloadButton")
};

async function loadReports() {
  els.rows.innerHTML = `<tr><td colspan="9">加载中...</td></tr>`;
  try {
    const index = await fetch("../index.json", { cache: "no-store" }).then(r => r.json());
    const reports = await Promise.all((index.reports || []).map(async item => {
      const report = await fetch(`../${item.path}`, { cache: "no-store" }).then(r => r.json());
      return { ...report, path: item.path };
    }));
    state.reports = reports.sort((a, b) => String(b.time).localeCompare(String(a.time)));
    applyFilters();
  } catch (error) {
    els.rows.innerHTML = `<tr><td colspan="9">未读取到 index.json，可先将报告和索引上传到服务器指定目录。</td></tr>`;
    els.detail.textContent = String(error);
    state.reports = [];
    state.filtered = [];
    renderStats();
  }
}

function applyFilters() {
  const keyword = els.search.value.trim().toLowerCase();
  const level = els.level.value;
  state.filtered = state.reports.filter(report => {
    const text = [
      report.app?.name,
      report.app?.bundleId,
      report.event,
      report.device?.model,
      report.page?.current
    ].join(" ").toLowerCase();
    return (!keyword || text.includes(keyword)) && (!level || report.level === level);
  });
  renderStats();
  renderRows();
}

function renderStats() {
  const total = state.reports.length;
  const critical = state.reports.filter(r => r.level === "critical").length;
  const warning = state.reports.filter(r => r.level === "warning").length;
  const apps = new Set(state.reports.map(r => r.app?.bundleId).filter(Boolean)).size;
  els.stats.innerHTML = [
    ["报告", total],
    ["严重", critical],
    ["警告", warning],
    ["App", apps]
  ].map(([label, value]) => `<div class="stat"><strong>${value}</strong><span>${label}</span></div>`).join("");
}

function renderRows() {
  if (!state.filtered.length) {
    els.rows.innerHTML = `<tr><td colspan="9">暂无匹配报告</td></tr>`;
    return;
  }
  els.rows.innerHTML = state.filtered.map((report, index) => `
    <tr data-index="${index}">
      <td>${safe(report.time)}</td>
      <td>${safe(report.app?.name)} ${safe(report.app?.version)}</td>
      <td><span class="badge ${safe(report.level)}">${safe(displayEvent(report.event))}</span></td>
      <td>${safe(report.page?.current || "unknown")}</td>
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
    DemoButtonTapped: "Demo 按钮点击"
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

els.search.addEventListener("input", applyFilters);
els.level.addEventListener("change", applyFilters);
els.reload.addEventListener("click", loadReports);
loadReports();
