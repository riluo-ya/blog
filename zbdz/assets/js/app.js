/* 柔造商品目录 · 本地离线版 */
(function () {
  "use strict";

  var DATA = null;
  var state = { lv1: "全部", lv2: "全部", query: "" };

  var grid = document.getElementById("grid");
  var empty = document.getElementById("empty");
  var resultMeta = document.getElementById("resultMeta");
  var lv1Chips = document.getElementById("lv1Chips");
  var lv2Chips = document.getElementById("lv2Chips");
  var searchInput = document.getElementById("search");
  var modalMask = document.getElementById("modalMask");
  var modalBody = document.getElementById("modalBody");
  var modalClose = document.getElementById("modalClose");

  function yuan(v) {
    if (v === null || v === undefined || v === "") return null;
    return Number(v).toFixed(2);
  }

  function escapeHtml(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function loadData() {
    return fetch("data/products.json")
      .then(function (r) {
        if (!r.ok) throw new Error("products.json 读取失败 (" + r.status + ")");
        return r.json();
      });
  }

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
      if (q && p.title.toLowerCase().indexOf(q) === -1) return false;
      return true;
    });
  }

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

  function vipTags(p) {
    var html = "";
    if (p.vip_price !== null && p.vip_price !== undefined) {
      html += '<span class="tag-vip">VIP ¥' + yuan(p.vip_price) + "</span>";
    }
    if (p.vip_promotion) {
      html += '<span class="tag-vip">会员 · ' + escapeHtml(p.vip_promotion) + "</span>";
    }
    return html ? '<div class="tags">' + html + "</div>" : "";
  }

  function cardHtml(p) {
    return (
      '<article class="card" data-id="' + p.id + '">' +
        '<div class="card-img">' +
          '<img src="' + escapeHtml(p.image) + '" alt="' + escapeHtml(p.title) + '" loading="lazy" />' +
        "</div>" +
        '<div class="card-body">' +
          '<div class="card-title">' + escapeHtml(p.title) + "</div>" +
          priceHtml(p) +
          vipTags(p) +
        "</div>" +
      "</article>"
    );
  }

  function renderGrid() {
    var list = filtered();
    grid.innerHTML = list.map(cardHtml).join("");
    empty.hidden = list.length !== 0;
    resultMeta.textContent = "共 " + list.length + " 件商品";

    Array.prototype.forEach.call(grid.querySelectorAll(".card"), function (el) {
      el.onclick = function () {
        var id = Number(el.getAttribute("data-id"));
        var p = DATA.products.find(function (x) { return x.id === id; });
        if (p) openModal(p);
      };
    });
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
      '<div class="modal-img"><img src="' + escapeHtml(p.image) + '" alt="' + escapeHtml(p.title) + '" /></div>' +
      '<div class="modal-info">' +
        "<h2>" + escapeHtml(p.title) + "</h2>" +
        '<div class="modal-cat">' + escapeHtml(p.category.lv1) + " / " + escapeHtml(p.category.lv2) + "</div>" +
        priceBlock +
        vipTags(p) +
        (p.price_note ? "" : tierRows(p)) +
      "</div>";
    modalMask.hidden = false;
  }

  function closeModal() { modalMask.hidden = true; }

  function renderAll() {
    renderLv1();
    renderLv2();
    renderGrid();
  }

  searchInput.addEventListener("input", function () {
    state.query = searchInput.value;
    renderGrid();
  });
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
