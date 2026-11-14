/* 柔造商品目录 · 本地离线版
 *
 * 本次改动：
 *  1) 取消全部 VIP 展示（数据里 vip_price / vip_promotion 已留空，页面不再渲染 VIP 区块）。
 *  2) 图片走 jsDelivr CDN，加载失败自动回退到本地相对路径，离线也能看。
 *  3) 首屏分页渲染（默认 48 件 + 「加载更多」），不再一次性请求 552 张图。
 *  4) 阶梯价数据只保留第一档（单价最高那档），详情弹窗表格相应只有一行。
 *
 * 只需维护下面 3 个配置项，其余不用动。
 */
(function () {
  "use strict";

  /* ===== 可配置项 ===== */
  // 图片 CDN 前缀。指向本仓库 main 分支的 zbdz/assets/images/。
  // 换成 commit hash 可固定版本；把 USE_CDN 设为 false 可完全走本地路径。
  var USE_CDN = true;
  var CDN_BASE = "https://cdn.jsdelivr.net/gh/riluo-ya/blog@main/zbdz/assets/images/";
  var PAGE_SIZE = 48;          // 首屏与每次「加载更多」的件数
  var IMG_W = 600, IMG_H = 600; // 图片实际尺寸，写死可避免加载时布局抖动

  var DATA = null;
  var state = { lv1: "全部", lv2: "全部", query: "" };
  var shown = PAGE_SIZE;       // 当前应显示多少件
  var rendered = 0;            // 当前已插入 DOM 多少件（增量渲染用）

  var grid = document.getElementById("grid");
  var empty = document.getElementById("empty");
  var resultMeta = document.getElementById("resultMeta");
  var lv1Chips = document.getElementById("lv1Chips");
  var lv2Chips = document.getElementById("lv2Chips");
  var searchInput = document.getElementById("search");
  var modalMask = document.getElementById("modalMask");
  var modalBody = document.getElementById("modalBody");
  var modalClose = document.getElementById("modalClose");
  var moreWrap = document.getElementById("moreWrap");
  var moreBtn = document.getElementById("moreBtn");

  function yuan(v) {
    if (v === null || v === undefined || v === "") return null;
    var n = Number(v);
    return isNaN(n) ? null : n.toFixed(2);
  }

  function escapeHtml(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /* ---------- 图片：CDN 优先，本地兜底 ---------- */
  /* onerror 挂全局，因为卡片是字符串拼出来的 */
  window.imgFallback = function (el) {
    if (el.getAttribute("data-failed")) return;   // 本地也失败就不再循环
    el.setAttribute("data-failed", "1");
    var local = el.getAttribute("data-local");
    if (local) el.src = local;
  };

  function imgTag(p, eager) {
    var src = String(p.image || "");
    var attrs;
    if (!src) {
      return '<div class="img-ph">暂无图片</div>';
    }
    if (!USE_CDN || /^(https?:\/\/|data:|\/)/i.test(src)) {
      attrs = 'src="' + escapeHtml(src) + '"';
    } else {
      // 只取文件名，避免本地路径层级和 CDN 目录对不上
      var file = src.split("/").pop();
      attrs = 'src="' + escapeHtml(CDN_BASE + file) + '" data-local="' + escapeHtml(src) +
        '" onerror="imgFallback(this)"';
    }
    return '<img ' + attrs +
      ' alt="' + escapeHtml(p.title) + '"' +
      ' width="' + IMG_W + '" height="' + IMG_H + '"' +
      ' loading="' + (eager ? "eager" : "lazy") + '" decoding="async">';
  }

  function loadData() {
    return fetch("data/products.json")
      .then(function (r) {
        if (!r.ok) throw new Error("products.json 读取失败 (" + r.status + ")");
        return r.json();
      });
  }

  /* ---------- 筛选 ---------- */
  function lv1List() {
    return DATA.categories.map(function (c) { return c.lv1; });
  }

  function lv2List(lv1) {
    if (lv1 === "全部") return [];
    var cat = DATA.categories.find(function (c) { return c.lv1 === lv1; });
    return cat ? cat.children : [];
  }

  function renderLv1() {
    var names = ["全部"].concat(lv1List());
    lv1Chips.innerHTML = "";
    names.forEach(function (name) {
      var b = document.createElement("button");
      b.className = "chip" + (state.lv1 === name ? " active" : "");
      b.textContent = name;
      b.onclick = function () {
        state.lv1 = name;
        state.lv2 = "全部";
        renderAll();
      };
      lv1Chips.appendChild(b);
    });
  }

  function renderLv2() {
    var subs = lv2List(state.lv1);
    lv2Chips.innerHTML = "";
    if (state.lv1 === "全部") { lv2Chips.style.display = "none"; return; }
    lv2Chips.style.display = "";
    ["全部"].concat(subs).forEach(function (name) {
      var b = document.createElement("button");
      b.className = "chip sub" + (state.lv2 === name ? " active" : "");
      b.textContent = name;
      b.onclick = function () { state.lv2 = name; renderAll(); };
      lv2Chips.appendChild(b);
    });
  }

  function filtered() {
    var q = state.query.trim().toLowerCase();
    return DATA.products.filter(function (p) {
      if (state.lv1 !== "全部" && p.category.lv1 !== state.lv1) return false;
      if (state.lv2 !== "全部" && p.category.lv2 !== state.lv2) return false;
      if (q && String(p.title).toLowerCase().indexOf(q) === -1) return false;
      return true;
    });
  }

  /* ---------- 价格 ---------- */
  function priceHtml(p) {
    if (p.price_note) {
      return '<div class="price-row"><span class="price-note">' + escapeHtml(p.price_note) + "</span></div>";
    }
    var y = yuan(p.price_first);
    if (y === null) {
      return '<div class="price-row"><span class="price-note">询价</span></div>';
    }
    return '<div class="price-row"><span class="price"><span class="yen">¥</span>' + y +
      '</span><span class="price-from">起</span></div>';
  }

  function cardHtml(p) {
    return (
      '<article class="card" data-id="' + escapeHtml(p.id) + '">' +
        '<div class="card-img">' + imgTag(p, false) + "</div>" +
        '<div class="card-body">' +
          '<div class="card-title">' + escapeHtml(p.title) + "</div>" +
          priceHtml(p) +
        "</div>" +
      "</article>"
    );
  }

  /* ---------- 列表：增量分页渲染 ---------- */
  function renderGrid(reset) {
    var list = filtered();
    if (reset) {
      shown = PAGE_SIZE;
      grid.innerHTML = "";
      rendered = 0;
    }
    var target = Math.min(shown, list.length);
    if (target > rendered) {
      // 只追加新增部分，已加载的图片不会因为重排而重新请求
      grid.insertAdjacentHTML("beforeend", list.slice(rendered, target).map(cardHtml).join(""));
      rendered = target;
    }
    empty.hidden = list.length !== 0;
    resultMeta.textContent = "共 " + list.length + " 件商品" +
      (list.length > rendered ? " · 已显示 " + rendered + " 件" : "");

    if (moreWrap) {
      var rest = list.length - rendered;
      moreWrap.hidden = rest <= 0;
      if (moreBtn) moreBtn.textContent = "加载更多（还有 " + rest + " 件）";
    }
  }

  function tierRows(p) {
    if (!p.price_tiers || !p.price_tiers.length) return "";
    var rows = p.price_tiers.map(function (t) {
      var y = yuan(t.price_yuan);
      return "<tr><td>≥ " + escapeHtml(t.count) + " 件</td><td>¥" + (y === null ? "—" : y) + "</td></tr>";
    }).join("");
    return '<table class="tier-table"><thead><tr><th>采购档位</th><th>单价</th></tr></thead><tbody>' + rows + "</tbody></table>";
  }

  function openModal(p) {
    var priceBlock = p.price_note
      ? '<div class="price-note">' + escapeHtml(p.price_note) + "</div>"
      : (yuan(p.price_first) !== null
          ? '<div class="price-row"><span class="price"><span class="yen">¥</span>' + yuan(p.price_first) +
            '</span><span class="price-from">起（第一档 / 1 件）</span></div>'
          : '<div class="price-note">询价</div>');

    modalBody.innerHTML =
      '<div class="modal-img">' + imgTag(p, true) + "</div>" +
      '<div class="modal-info">' +
        "<h2>" + escapeHtml(p.title) + "</h2>" +
        '<div class="modal-cat">' + escapeHtml(p.category.lv1) + " / " + escapeHtml(p.category.lv2) + "</div>" +
        priceBlock +
        (p.price_note ? "" : tierRows(p)) +
      "</div>";
    modalMask.hidden = false;
  }

  function closeModal() { modalMask.hidden = true; }

  function renderAll() {
    renderLv1();
    renderLv2();
    renderGrid(true);
  }

  /* ---------- 事件 ---------- */
  // 事件委托只绑一次，增量追加卡片不用重复绑定
  grid.addEventListener("click", function (e) {
    var el = e.target && e.target.closest ? e.target.closest(".card") : null;
    if (!el || !DATA) return;
    var id = Number(el.getAttribute("data-id"));
    var p = DATA.products.find(function (x) { return x.id === id; });
    if (p) openModal(p);
  });

  searchInput.addEventListener("input", function () {
    state.query = searchInput.value;
    renderGrid(true);
  });
  if (moreBtn) {
    moreBtn.addEventListener("click", function () {
      shown += PAGE_SIZE;
      renderGrid(false);
    });
  }
  modalClose.addEventListener("click", closeModal);
  modalMask.addEventListener("click", function (e) {
    if (e.target === modalMask) closeModal();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") closeModal();
  });

  loadData().then(function (data) {
    DATA = data;
    document.getElementById("subtitle").textContent =
      "当前 · 共 " + DATA.count + " 件商品";
    renderAll();
  }).catch(function (e) {
    grid.innerHTML = "";
    empty.hidden = false;
    empty.textContent = "数据加载失败：" + e.message + "。请通过本地静态服务或部署到网页后访问（浏览器直接双击打开本地文件时，会禁止读取 products.json）。";
  });
})();
