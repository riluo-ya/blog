/* 周边定制商品目录 · 本地离线版
 *
 * 当前口径：
 *  - 无会员价、无满减文案；阶梯价只保留第一档（数据层已处理）。
 *  - 没有「点开看详情」弹窗：一个档位，卡片上直接展示完。
 *  - 价格写作「¥1.13元」，分类名以淡灰小方框贴在价格一旁。
 *  - 一级 / 二级分类分成两层，视觉上明确从属关系。
 *  - 一旦使用搜索，就忽略当前分类，在全部商品里搜。
 *  - 图片走 jsDelivr CDN，加载中显示骨架动画，失败回退本地、再失败回退文字。
 *  - image 为空的商品不引用图片：有 image_text 就渲染成纯文字海报（不复刻品牌），
 *    否则退回商品名文字块。「自定义亚克力」的原图是带品牌 logo 的宣传图，
 *    现已改为不含品牌名的文字版。
 *  - 首屏 48 件 + 「加载更多」，避免一次请求 552 张图。
 *
 * 只需维护下面几个配置项，其余不用动。
 */
(function () {
  "use strict";

  var USE_CDN = true;
  var CDN_BASE = "https://cdn.jsdelivr.net/gh/riluo-ya/blog@main/zbdz/assets/images/";
  var PAGE_SIZE = 48;
  var IMG_W = 600, IMG_H = 600;

  var DATA = null;
  var state = { lv1: "全部", lv2: "全部", query: "" };
  var shown = PAGE_SIZE;
  var rendered = 0;
  var seq = 0;                 // 卡片进场动画的序号

  var grid = document.getElementById("grid");
  var empty = document.getElementById("empty");
  var resultMeta = document.getElementById("resultMeta");
  var lv1Chips = document.getElementById("lv1Chips");
  var lv2Chips = document.getElementById("lv2Chips");
  var lv2Group = document.getElementById("lv2Group");
  var searchInput = document.getElementById("search");
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

  /* ---------- 图片：骨架动画 → 淡入，CDN 失败回退本地 ---------- */
  window.imgDone = function (el) {
    el.classList.add("is-loaded");
    var box = el.parentNode;
    if (box) {
      var sk = box.querySelector(".img-skeleton");
      if (sk) sk.classList.add("is-gone");
    }
  };

  window.imgFallback = function (el) {
    if (el.getAttribute("data-failed")) {   // 本地也失败了，换成文字占位
      var box = el.parentNode;
      if (box) box.innerHTML = textPlaceholder(el.getAttribute("alt"));
      return;
    }
    el.setAttribute("data-failed", "1");
    var local = el.getAttribute("data-local");
    if (local) {
      el.src = local;                       // 回退本地，onload 仍会走 imgDone
    } else {
      var b = el.parentNode;
      if (b) b.innerHTML = textPlaceholder(el.getAttribute("alt"));
    }
  };

  /* 图片缺失时用商品名做文字块，带淡入动画，不会是光秃秃的白框 */
  function textPlaceholder(title) {
    return '<div class="img-text"><span class="img-text-main">' +
      escapeHtml(title || "商品") + '</span>' +
      '<span class="img-text-sub">图片以文字展示</span></div>';
  }

  /* 纯文字海报：把原本那张宣传图的内容改成文字排版。
     只取 headline / items / new_at 三个字段，不含任何品牌标识。 */
  function imageTextHtml(p) {
    var t = p.image_text;
    if (!t || typeof t !== "object") return textPlaceholder(p.title);
    var hl = String(t.headline == null ? "" : t.headline).trim();
    var items = Array.isArray(t.items)
      ? t.items.map(function (x) { return String(x == null ? "" : x).trim(); }).filter(Boolean)
      : [];
    if (!hl && !items.length) return textPlaceholder(p.title);
    var newAt = parseInt(t.new_at, 10) || 0;
    return '<div class="img-poster">' +
      (hl ? '<div class="ip-head">' + escapeHtml(hl) + "</div>" : "") +
      '<ul class="ip-list">' + items.map(function (x, k) {
        return '<li><span class="ip-check">✓</span>' +
          '<span class="ip-txt">' + escapeHtml(x) +
          (k + 1 === newAt ? '<span class="ip-new">NEW</span>' : "") +
          "</span></li>";
      }).join("") + "</ul></div>";
  }

  function imgTag(p) {
    var src = String(p.image || "");
    if (!src) return imageTextHtml(p);

    var attrs;
    if (!USE_CDN || /^(https?:\/\/|data:|\/)/i.test(src)) {
      attrs = 'src="' + escapeHtml(src) + '"';
    } else {
      var file = src.split("/").pop();
      attrs = 'src="' + escapeHtml(CDN_BASE + file) + '" data-local="' + escapeHtml(src) + '"';
    }
    return '<div class="img-skeleton" aria-hidden="true"><span class="sk-ico">🖼</span></div>' +
      '<img class="card-photo" ' + attrs +
      ' alt="' + escapeHtml(p.title) + '"' +
      ' width="' + IMG_W + '" height="' + IMG_H + '"' +
      ' loading="lazy" decoding="async"' +
      ' onload="imgDone(this)" onerror="imgFallback(this)">';
  }

  function loadData() {
    return fetch("data/products.json")
      .then(function (r) {
        if (!r.ok) throw new Error("products.json 读取失败 (" + r.status + ")");
        return r.json();
      });
  }

  /* ---------- 分类：一级 / 二级两层 ---------- */
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
    if (state.lv1 === "全部") {
      lv2Group.hidden = true;
      return;
    }
    lv2Group.hidden = false;
    var label = document.getElementById("lv2Label");
    if (label) label.textContent = state.lv1 + " · 二级分类";
    ["全部"].concat(subs).forEach(function (name) {
      var b = document.createElement("button");
      b.className = "chip sub" + (state.lv2 === name ? " active" : "");
      b.textContent = name;
      b.onclick = function () { state.lv2 = name; renderGrid(true); };
      lv2Chips.appendChild(b);
    });
  }

  /* 搜索时直接展示全部：q 非空则忽略分类条件 */
  function filtered() {
    var q = state.query.trim().toLowerCase();
    var searching = q.length > 0;
    return DATA.products.filter(function (p) {
      if (!searching) {
        if (state.lv1 !== "全部" && p.category.lv1 !== state.lv1) return false;
        if (state.lv2 !== "全部" && p.category.lv2 !== state.lv2) return false;
      }
      if (q && String(p.title).toLowerCase().indexOf(q) === -1) return false;
      return true;
    });
  }

  /* ---------- 价格 / 分类小方框 ---------- */
  function priceInner(p) {
    if (p.price_note) {
      return '<span class="price-note">' + escapeHtml(p.price_note) + "</span>";
    }
    var y = yuan(p.price_first);
    if (y === null) return '<span class="price-note">询价</span>';
    return '<span class="price"><span class="yen">¥</span>' + y +
      '</span><span class="price-unit">元</span>';
  }

  /* 灰色分类文字挪到卡片上：淡到不抢眼的小方框，鼠标悬停可看完整一级/二级 */
  function catChipHtml(p) {
    var lv1 = p.category.lv1 || "";
    var lv2 = p.category.lv2 || "";
    if (!lv1 && !lv2) return "";
    return '<span class="cat-chip" title="' + escapeHtml(lv1 + " / " + lv2) + '">' +
      escapeHtml(lv2 || lv1) + "</span>";
  }

  function cardHtml(p, n) {
    return (
      '<article class="card" style="--i:' + (n % 12) + '">' +
        '<div class="card-img">' + imgTag(p) + "</div>" +
        '<div class="card-body">' +
          '<div class="card-title">' + escapeHtml(p.title) + "</div>" +
          '<div class="price-row">' + priceInner(p) + catChipHtml(p) + "</div>" +
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
      seq = 0;
    }
    var target = Math.min(shown, list.length);
    if (target > rendered) {
      var start = seq;
      grid.insertAdjacentHTML("beforeend",
        list.slice(rendered, target).map(function (p, k) {
          return cardHtml(p, start + k);
        }).join(""));
      seq += target - rendered;
      rendered = target;
      // 图片可能已在缓存里，onload 不会触发，手动补一次淡入
      Array.prototype.forEach.call(grid.querySelectorAll(".card-photo:not(.is-loaded)"), function (im) {
        if (im.complete && im.naturalWidth > 0) window.imgDone(im);
      });
    }

    var searching = state.query.trim().length > 0;
    empty.hidden = list.length !== 0;
    resultMeta.textContent = "共 " + list.length + " 件商品" +
      (searching ? " · 搜索范围：全部商品" : "") +
      (list.length > rendered ? " · 已显示 " + rendered + " 件" : "");
    resultMeta.classList.toggle("is-searching", searching);

    if (moreWrap) {
      var rest = list.length - rendered;
      moreWrap.hidden = rest <= 0;
      if (moreBtn) moreBtn.textContent = "加载更多（还有 " + rest + " 件）";
    }
  }

  function renderAll() {
    renderLv1();
    renderLv2();
    renderGrid(true);
  }

  /* ---------- 事件 ---------- */
  searchInput.addEventListener("input", function () {
    state.query = searchInput.value;
    if (state.query.trim()) {
      // 用搜索就直接展示全部，不再受当前分类限制
      state.lv1 = "全部";
      state.lv2 = "全部";
    }
    renderAll();
  });

  if (moreBtn) {
    moreBtn.addEventListener("click", function () {
      shown += PAGE_SIZE;
      renderGrid(false);
    });
  }

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
