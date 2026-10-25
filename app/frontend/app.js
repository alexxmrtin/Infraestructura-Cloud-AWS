const config = window.SHOPFLOW_CONFIG;
const $ = (id) => document.getElementById(id);

let products = [];
let cart = [];

function base64Url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeJwt(token) {
  const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(decodeURIComponent(escape(atob(payload))));
}

function session() {
  const accessToken = sessionStorage.getItem("access_token");
  const idToken = sessionStorage.getItem("id_token");
  if (!accessToken || !idToken) return null;
  if (decodeJwt(accessToken).exp * 1000 < Date.now()) {
    sessionStorage.clear();
    return null;
  }
  return { accessToken, email: decodeJwt(idToken).email };
}

async function login() {
  const verifier = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  sessionStorage.setItem("pkce_verifier", verifier);

  const params = new URLSearchParams({
    client_id: config.clientId,
    response_type: "code",
    scope: "openid email profile",
    redirect_uri: config.redirectUri,
    code_challenge_method: "S256",
    code_challenge: base64Url(new Uint8Array(digest)),
  });
  location.assign(`${config.authDomain}/oauth2/authorize?${params}`);
}

function logout() {
  sessionStorage.clear();
  const params = new URLSearchParams({ client_id: config.clientId, logout_uri: config.redirectUri });
  location.assign(`${config.authDomain}/logout?${params}`);
}

async function finishLogin(code) {
  const response = await fetch(`${config.authDomain}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: config.clientId,
      code,
      redirect_uri: config.redirectUri,
      code_verifier: sessionStorage.getItem("pkce_verifier") || "",
    }),
  });
  sessionStorage.removeItem("pkce_verifier");
  history.replaceState(null, "", "/");
  if (!response.ok) return;

  const tokens = await response.json();
  sessionStorage.setItem("access_token", tokens.access_token);
  sessionStorage.setItem("id_token", tokens.id_token);
}

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  const current = session();
  if (current) headers.Authorization = `Bearer ${current.accessToken}`;
  if (options.body) headers["Content-Type"] = "application/json";
  return fetch(`/api${path}`, { ...options, headers });
}

function renderProducts() {
  const logged = Boolean(session());
  $("products").replaceChildren(
    ...products.map((p) => {
      const li = document.createElement("li");
      const stock = p.stock === null || p.stock === undefined ? "" : ` · quedan ${p.stock}`;
      li.textContent = `${p.name} · ${p.price.toFixed(2)} €${stock}`;
      const button = document.createElement("button");
      button.textContent = "Añadir";
      button.disabled = !logged;
      button.onclick = () => addToCart(p.id);
      li.append(button);
      return li;
    })
  );
}

function renderCart() {
  const names = Object.fromEntries(products.map((p) => [p.id, p.name]));
  $("cart").replaceChildren(
    ...cart.map((item) => {
      const li = document.createElement("li");
      li.textContent = `${names[item.product_id] || `Producto ${item.product_id}`} × ${item.quantity}`;
      return li;
    })
  );
  $("clear").hidden = cart.length === 0;
  $("order").hidden = cart.length === 0;
  if (session()) $("cart-hint").textContent = cart.length ? "Se borra solo a las 24 horas." : "Tu carrito está vacío.";
}

async function loadProducts() {
  const response = await api("/products");
  if (!response.ok) {
    $("source").textContent = `La API ha contestado ${response.status}.`;
    return;
  }
  const data = await response.json();
  products = data.products;
  $("source").textContent = data.source === "cache" ? "Leído de la caché (Valkey)." : "Leído de la base de datos (RDS).";
  renderProducts();
}

async function loadCart() {
  if (!session()) return;
  const response = await api("/cart");
  cart = response.ok ? (await response.json()).items : [];
  renderCart();
}

async function saveCart() {
  await api("/cart", { method: "PUT", body: JSON.stringify({ items: cart }) });
  renderCart();
}

async function addToCart(productId) {
  const item = cart.find((i) => i.product_id === productId);
  if (item) item.quantity += 1;
  else cart.push({ product_id: productId, quantity: 1 });
  await saveCart();
}

async function clearCart() {
  await api("/cart", { method: "DELETE" });
  cart = [];
  renderCart();
}

const STATUS = { PENDING: "En proceso", CONFIRMED: "Confirmado", FAILED: "Rechazado" };
const REASONS = { OutOfStock: "sin stock", PaymentDeclined: "pago rechazado" };

function renderOrders(orders) {
  $("orders").replaceChildren(
    ...orders.map((o) => {
      const li = document.createElement("li");
      const units = o.items.reduce((sum, i) => sum + i.quantity, 0);
      const reason = o.failure_reason ? ` (${REASONS[o.failure_reason] || o.failure_reason})` : "";
      li.textContent = `${o.created_at.slice(0, 16).replace("T", " ")} · ${units} uds · ${o.total} € · ${STATUS[o.status] || o.status}${reason}`;
      if (o.has_invoice) {
        const button = document.createElement("button");
        button.textContent = "Factura";
        button.onclick = () => openInvoice(o.order_id);
        li.append(button);
      }
      return li;
    })
  );
  $("orders-hint").textContent = orders.length ? "El pedido tarda unos segundos en procesarse." : "Todavía no tienes pedidos.";
}

async function loadOrders() {
  if (!session()) return;
  $("refresh-orders").hidden = false;
  const response = await api("/orders");
  if (response.ok) renderOrders((await response.json()).orders);
}

async function placeOrder() {
  $("order").disabled = true;
  const response = await api("/orders", { method: "POST" });
  $("order").disabled = false;
  if (!response.ok) {
    $("cart-hint").textContent = `No se ha podido hacer el pedido (${response.status}).`;
    return;
  }
  cart = [];
  renderCart();
  await loadOrders();
  setTimeout(async () => {
    await loadOrders();
    await loadProducts();
  }, 5000);
}

async function openInvoice(orderId) {
  const response = await api(`/orders/${orderId}/invoice`);
  if (response.ok) window.open((await response.json()).url, "_blank", "noopener");
}

async function loadInfo() {
  const response = await api("/info");
  if (!response.ok) return;
  const data = await response.json();
  $("info").textContent = `Tarea ${data.task} en ${data.availability_zone || "zona desconocida"}. Recarga para ver cómo reparte el ALB.`;
}

async function main() {
  const code = new URLSearchParams(location.search).get("code");
  if (code) await finishLogin(code);

  const current = session();
  $("user").textContent = current ? current.email : "";
  $("login").hidden = Boolean(current);
  $("logout").hidden = !current;
  $("login").onclick = login;
  $("logout").onclick = logout;
  $("clear").onclick = clearCart;
  $("order").onclick = placeOrder;
  $("refresh-orders").onclick = loadOrders;

  await loadProducts();
  await loadCart();
  await loadOrders();
  await loadInfo();
}

main();
