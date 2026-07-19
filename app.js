// ============================================================
//  Casri POS — main application
// ============================================================
// Architecture: single-page vanilla JS SPA, all state in localStorage.
// Add Firebase later for cloud sync (same pattern as Isguul).

var LANG="en",PAGE="dashboard",CURRENT_USER=null,CURRENCY="USD";
var FX_USD_TO_SOS=580, FX_USD_TO_SLSH=8500;   // rates editable in Settings
var CAT_FILTER="all", CART=[];

// ── PERSISTENCE HELPERS ──────────────────────────────────────
function _load(key,fallback){try{var s=localStorage.getItem(key);if(s)return JSON.parse(s);}catch(e){}return fallback;}
function _save(key,val){try{localStorage.setItem(key,JSON.stringify(val));}catch(e){toast("Storage full");}}

// ── DATA ─────────────────────────────────────────────────────
// ── MULTI-BUSINESS DATA ─────────────────────────────────────
// An admin can run multiple Casri POS businesses from one install. Each
// business has its own settings, products, and sales. The active business is
// kept in CURRENT_BIZ_ID and persists across reloads.
var BIZ_LIST=_load("pos_biz_list",null);
var CURRENT_BIZ_ID=_load("pos_current_biz","");
// Migration: if the old single-business storage (pos_biz) exists but the new
// multi-business list does not, wrap the single record into a list.
if(!BIZ_LIST){
  var oldBiz=_load("pos_biz",null);
  if(oldBiz){
    oldBiz.id=oldBiz.id||"b1";
    BIZ_LIST=[oldBiz];
    CURRENT_BIZ_ID=oldBiz.id;
  } else {
    BIZ_LIST=[{id:"b1",name:"Casri POS",addr:"",phone:"",tax:0,currency:"USD",type:"shop"}];
    CURRENT_BIZ_ID="b1";
  }
  _save("pos_biz_list",BIZ_LIST);
  _save("pos_current_biz",CURRENT_BIZ_ID);
}
// Backfill any business missing required fields
BIZ_LIST.forEach(function(b){if(!b.id)b.id="b"+Date.now();if(!b.type)b.type="shop";if(b.name==="Smart POS"||b.name==="SmartPOS")b.name="Casri POS";});
// Ensure CURRENT_BIZ_ID points at a real business
if(!BIZ_LIST.find(function(b){return b.id===CURRENT_BIZ_ID;})){CURRENT_BIZ_ID=BIZ_LIST[0].id;_save("pos_current_biz",CURRENT_BIZ_ID);}
function gB(){return BIZ_LIST.find(function(b){return b.id===CURRENT_BIZ_ID;})||BIZ_LIST[0];}
// Legacy BIZ alias — every page still reads BIZ.something; keep it pointing at
// the active business via a property accessor pattern.
var BIZ=new Proxy({},{
  get:function(t,k){var b=gB();return b?b[k]:undefined;},
  set:function(t,k,v){var b=gB();if(b)b[k]=v;return true;}
});
function _saveBiz(){_save("pos_biz_list",BIZ_LIST);_save("pos_current_biz",CURRENT_BIZ_ID);}
function switchBiz(bid){
  // Only the super-admin may change the active business. Without this guard a
  // business-scoped user could switch to another business and read its products,
  // sales and takings.
  if(!isSuperAdmin()){toast(T("Not allowed","Lama ogoolayn"));return;}
  if(!BIZ_LIST.find(function(b){return b.id===bid;}))return;
  CURRENT_BIZ_ID=bid;
  _save("pos_current_biz",CURRENT_BIZ_ID);
  CART=[];TABLE_NO="";   // reset POS state on switch
  CURRENCY=BIZ.currency||"USD";
  renderUser();buildNav();renderPage("dashboard");
  toast(T("Switched to ","Loo wareejiyay ")+(BIZ.name||"-"));
}
CURRENCY=BIZ.currency||"USD";

// Business types — each one customises the POS terminal slightly.
// 'shop'       (default) — simple over-the-counter retail, no extras
// 'retail'     — adds barcode/SKU scan field above the cart
// 'restaurant' — adds table number + order type (Dine-in/Takeaway/Delivery)
// 'cafe'       — same as restaurant but with cafe-leaning sample categories
// 'bar'        — same as restaurant but bar-leaning
var BIZ_TYPES=[
  {k:"shop",       en:"Shop / General store", so:"Dukaan",      ic:"🏪"},
  {k:"retail",     en:"Retail (barcoded)",     so:"Tafaariiq",   ic:"📦"},
  {k:"restaurant", en:"Restaurant",            so:"Maqaayad",    ic:"🍽️"},
  {k:"cafe",       en:"Cafe",                  so:"Kafee",       ic:"☕"},
  {k:"bar",        en:"Juice / Tea bar",       so:"Baar Casiir",  ic:"🍵"}
];
function _bizUsesTables(){return ["restaurant","cafe","bar"].indexOf(BIZ.type)>=0;}
function _bizUsesBarcode(){return BIZ.type==="retail";}
// Active POS terminal state
var TABLE_NO="", ORDER_TYPE="Dine-in";

var ACCOUNTS=_load("pos_acc",[
  {id:"a1",username:"admin",password:"admin123",name:"Admin",role:"admin",active:true},
  {id:"a2",username:"cashier",password:"cash123",name:"Cashier",role:"cashier",active:true}
]);
var PRODUCTS=_load("pos_prod",[
  {id:"p1",name:"Coca-Cola 500ml",cat:"Drinks",price:1.50,stock:50,icon:"🥤"},
  {id:"p2",name:"Bottled Water",cat:"Drinks",price:0.75,stock:100,icon:"💧"},
  {id:"p3",name:"Bread",cat:"Bakery",price:1.20,stock:30,icon:"🍞"},
  {id:"p4",name:"Croissant",cat:"Bakery",price:1.80,stock:20,icon:"🥐"},
  {id:"p5",name:"Banana (per kg)",cat:"Produce",price:1.40,stock:25,icon:"🍌"},
  {id:"p6",name:"Apple (per kg)",cat:"Produce",price:2.20,stock:40,icon:"🍎"},
  {id:"p7",name:"Rice 1kg",cat:"Grocery",price:2.00,stock:60,icon:"🍚"},
  {id:"p8",name:"Sugar 1kg",cat:"Grocery",price:1.50,stock:45,icon:"☕"},
  {id:"p9",name:"Soap Bar",cat:"Household",price:1.00,stock:80,icon:"🧼"},
  {id:"p10",name:"Toothpaste",cat:"Household",price:2.50,stock:25,icon:"🦷"}
]);
var SALES=_load("pos_sales",[]);
// Backfill bizId on legacy products and sales so they show up under the
// original business after the multi-business migration.
(function _stampBizIds(){
  var changedP=false,changedS=false;
  PRODUCTS.forEach(function(p){if(!p.bizId){p.bizId=CURRENT_BIZ_ID;changedP=true;}});
  SALES.forEach(function(s){if(!s.bizId){s.bizId=CURRENT_BIZ_ID;changedS=true;}});
  if(changedP)_save("pos_prod",PRODUCTS);
  if(changedS)_save("pos_sales",SALES);
})();
// Helpers — every query now scopes by the active business.
function forBiz(arr){return (arr||[]).filter(function(x){return x&&x.bizId===CURRENT_BIZ_ID;});}

// ── I18N ─────────────────────────────────────────────────────
function T(en,so){return LANG==="so"?(so||en):en;}

// ── MONEY ────────────────────────────────────────────────────
// All prices stored in USD; display converts on the fly.
function money(usd){
  if(typeof usd!=="number"||isNaN(usd))usd=0;
  if(CURRENCY==="SOS")return "Sh "+Math.round(usd*FX_USD_TO_SOS).toLocaleString();
  if(CURRENCY==="SLSH")return "SlSh "+Math.round(usd*FX_USD_TO_SLSH).toLocaleString();
  return "$"+usd.toFixed(2);
}

// ── UI HELPERS ───────────────────────────────────────────────
function $(id){return document.getElementById(id);}
function esc(s){return ((s||"")+"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");}
function toast(msg){var t=$("toast");if(!t)return;t.textContent=msg;t.classList.add("show");clearTimeout(toast._t);toast._t=setTimeout(function(){t.classList.remove("show");},2200);}
function openM(id){var m=$(id);if(m)m.classList.add("open");}
async function closeM(id){var m=$(id);if(m)m.classList.remove("open");}

// ── IN-APP DIALOGS (native confirm/prompt/alert are IGNORED in the WebView) ──
// Awaitable: use `if(!await igAsk(...))return;` and `var v=await igAskText(...)`.
var _IG_YES=null,_IG_NO=null;
function igConfirm(text,onYes,yesLabel,onNo){
  _IG_YES=onYes||null;_IG_NO=onNo||null;
  var t=$("cf_title");if(t)t.textContent=T("Are you sure?","Ma hubtaa?");
  var x=$("cf_text");if(x)x.textContent=text||"";
  var no=$("cf_no");if(no)no.textContent=T("Cancel","Jooji");
  var y=$("cf_yes");if(y)y.textContent=yesLabel||T("Yes","Haa");
  if(!$("M_confirm")){if(onYes)onYes();return;}
  openM("M_confirm");
}
function igConfirmYes(){var cb=_IG_YES;_IG_YES=_IG_NO=null;closeM("M_confirm");if(typeof cb==="function")cb();}
function igConfirmNo(){var cb=_IG_NO;_IG_YES=_IG_NO=null;closeM("M_confirm");if(typeof cb==="function")cb();}
function igAsk(text,yesLabel){return new Promise(function(res){igConfirm(text,function(){res(true);},yesLabel,function(){res(false);});});}

var _IG_POK=null,_IG_PNO=null;
function igPrompt(text,defVal,onOk,onCancel){
  _IG_POK=onOk||null;_IG_PNO=onCancel||null;
  var t=$("pr_title");if(t)t.textContent=text||T("Enter value","Geli qiimaha");
  var x=$("pr_text");if(x)x.textContent="";
  var i=$("pr_input");if(i)i.value=defVal==null?"":String(defVal);
  var no=$("pr_no");if(no)no.textContent=T("Cancel","Jooji");
  var ok=$("pr_ok");if(ok)ok.textContent=T("OK","Haa");
  if(!$("M_prompt")){if(onCancel)onCancel();return;}
  openM("M_prompt");
  if(i)setTimeout(function(){i.focus();i.select();},50);
}
function igPromptOk(){var i=$("pr_input");var v=i?i.value:"";var cb=_IG_POK;_IG_POK=_IG_PNO=null;closeM("M_prompt");if(typeof cb==="function")cb(v);}
function igPromptCancel(){var cb=_IG_PNO;_IG_POK=_IG_PNO=null;closeM("M_prompt");if(typeof cb==="function")cb(null);}
function igAskText(text,defVal){return new Promise(function(res){igPrompt(text,defVal,function(v){res(v);},function(){res(null);});});}

var _IG_AOK=null;
function igAlert(text,onOk,title){
  _IG_AOK=onOk||null;
  var t=$("al_title");if(t)t.textContent=title||"Casri POS";
  var x=$("al_text");if(x)x.textContent=text||"";
  var ok=$("al_ok");if(ok)ok.textContent=T("OK","Haa");
  if(!$("M_alert")){if(onOk)onOk();return;}
  openM("M_alert");
}
function igAlertOk(){var cb=_IG_AOK;_IG_AOK=null;closeM("M_alert");if(typeof cb==="function")cb();}
function openSidebar(){$("sidebar").classList.add("open");$("sbOverlay").classList.add("open");}
function closeSidebar(){$("sidebar").classList.remove("open");$("sbOverlay").classList.remove("open");}

// ── LOGIN ────────────────────────────────────────────────────
function doLogin(){
  var u=$("loginUser").value.trim(),p=$("loginPass").value;
  var acc=ACCOUNTS.find(function(a){return a.active&&a.username.toLowerCase()===u.toLowerCase()&&a.password===p;});
  if(!acc){$("loginErr").style.display="block";return;}
  CURRENT_USER=acc;
  // If the account is scoped to a specific business, lock the active business
  // to that one. Super-admins (no bizId) keep whichever business they left on.
  if(acc.bizId){
    if(BIZ_LIST.find(function(b){return b.id===acc.bizId;})){
      CURRENT_BIZ_ID=acc.bizId;
      _save("pos_current_biz",CURRENT_BIZ_ID);
      CURRENCY=BIZ.currency||"USD";
    }
  }
  $("LP").style.display="none";
  $("AP").classList.add("open");
  buildNav();renderUser();
  setLang(LANG);
  goTo("dashboard");
}
// True when the active user is a super-admin (can switch businesses, edit
// the master Businesses list). Per-business admins are scoped to their bizId.
function isSuperAdmin(){return CURRENT_USER&&CURRENT_USER.role==="admin"&&!CURRENT_USER.bizId;}
function isBizAdmin(){return CURRENT_USER&&CURRENT_USER.role==="admin"&&!!CURRENT_USER.bizId;}
async function doLogout(){
  if(!await igAsk(T("Sign out?","Ka bax?")))return;
  CURRENT_USER=null;CART=[];
  $("AP").classList.remove("open");
  $("LP").style.display="flex";
  $("loginPass").value="";
}

// ── LANGUAGE TOGGLE ──────────────────────────────────────────
function setLang(l){
  LANG=l;
  $("langEN").classList.toggle("on",l==="en");
  $("langSO").classList.toggle("on",l==="so");
  if(CURRENT_USER){buildNav();renderUser();renderPage(PAGE);}
}

// ── SIDEBAR NAV ──────────────────────────────────────────────
var NAV_ALL=[
  {id:"dashboard", en:"Dashboard",     so:"Guriga",          ic:"🏠"},
  {id:"pos",       en:"POS Terminal",  so:"Iibka",           ic:"💳"},
  {id:"products",  en:"Products",      so:"Alaabta",         ic:"📦"},
  {id:"sales",     en:"Sales History", so:"Taariikhda Iibka",ic:"📜"},
  {id:"reports",   en:"Reports",       so:"Warbixinno",      ic:"📊"},
  {id:"businesses",en:"Businesses",    so:"Ganacsiyada",     ic:"🏢", admin:true},
  {id:"users",     en:"Users",         so:"Isticmaalayaal",  ic:"👥", admin:true},
  {id:"settings",  en:"Settings",      so:"Habayn",          ic:"⚙️", admin:true}
];
function buildNav(){
  var nav=$("sbNav"),h="";
  // Super-admin: business switcher dropdown.
  // Per-business admin / cashier: just show the locked business name.
  if(isSuperAdmin()&&BIZ_LIST.length>1){
    h+="<div style=\"padding:8px 14px 12px\">";
    h+="<div style=\"font-size:9px;color:rgba(255,255,255,.4);text-transform:uppercase;letter-spacing:.05em;margin-bottom:5px;font-weight:700\">"+T("Active business","Ganacsi firfircoon")+"</div>";
    h+="<select onchange=\"switchBiz(this.value)\" style=\"width:100%;background:rgba(255,255,255,.08);color:#fff;border:1px solid rgba(255,255,255,.15);border-radius:6px;padding:6px 9px;font-size:12px\">";
    BIZ_LIST.forEach(function(b){
      h+="<option value=\""+b.id+"\""+(b.id===CURRENT_BIZ_ID?" selected":"")+" style=\"background:#0a1628\">"+esc(b.name||"-")+"</option>";
    });
    h+="</select></div>";
  } else if(CURRENT_USER){
    h+="<div style=\"padding:8px 14px 12px;font-size:11px;color:rgba(255,255,255,.55)\">&#127970; "+esc((gB()&&gB().name)||"-")+"</div>";
  }
  NAV_ALL.forEach(function(it){
    if(it.admin&&CURRENT_USER.role!=="admin")return;
    // Businesses page is super-admin only — per-business admins can't see the master list.
    if(it.id==="businesses"&&!isSuperAdmin())return;
    var on=PAGE===it.id?" on":"";
    h+="<div class=\"sbIt"+on+"\" onclick=\"goTo('"+it.id+"');closeSidebar()\">";
    h+="<span class=\"sbIc\">"+it.ic+"</span>"+T(it.en,it.so);
    h+="</div>";
  });
  nav.innerHTML=h;
}
function renderUser(){
  $("sbBiz").textContent=BIZ.name||"Casri POS";
  var n=CURRENT_USER.name||"User";
  $("sbAv").textContent=n.split(" ").map(function(w){return w[0]||"";}).join("").slice(0,2).toUpperCase();
  $("sbNm").textContent=n;
  $("sbRl").textContent=CURRENT_USER.role==="admin"?T("Administrator","Maamulaha"):T("Cashier","Iibiyaha");
  var so=$("sbOutTxt");if(so)so.textContent=T("Sign out","Ka bax");
}

// ── PAGE ROUTER ──────────────────────────────────────────────
var PAGES={};
function goTo(id){PAGE=id;buildNav();renderPage(id);}
function renderPage(id){
  var area=$("PA");if(!area)return;
  // SCOPE GUARD — a business-scoped user's active business can never drift to
  // another business (stale saved state, a switch attempt, a shared device).
  // Every page reads data through forBiz(CURRENT_BIZ_ID), so pinning it here
  // keeps one business's products/sales/takings invisible to another's staff.
  if(CURRENT_USER&&CURRENT_USER.bizId&&CURRENT_BIZ_ID!==CURRENT_USER.bizId){
    if(BIZ_LIST.find(function(b){return b.id===CURRENT_USER.bizId;})){
      CURRENT_BIZ_ID=CURRENT_USER.bizId;
      _save("pos_current_biz",CURRENT_BIZ_ID);
    }
  }
  // Businesses page is super-admin only — block direct navigation, not just the nav link.
  if(id==="businesses"&&!isSuperAdmin())id="dashboard";
  var fn=PAGES[id]||PAGES.dashboard;
  try{
    var html=fn();
    area.innerHTML=html;
    $("tbT").textContent=_pageTitle(id);
  }catch(e){
    area.innerHTML="<div style=\"padding:30px;color:#bf2600\">Error: "+esc(e.message)+
      "<br><button class=\"btn btnP\" style=\"margin-top:10px\" onclick=\"goTo('dashboard')\">Back</button></div>";
    console.warn("renderPage error",e);
  }
}
function _pageTitle(id){var it=NAV_ALL.find(function(x){return x.id===id;});return it?T(it.en,it.so):id;}

// ============================================================
//  PAGE: DASHBOARD
// ============================================================
PAGES.dashboard=function(){
  var today=new Date().toISOString().slice(0,10);
  var bizSales=forBiz(SALES);
  var bizProducts=forBiz(PRODUCTS);
  var todaySales=bizSales.filter(function(s){return s.date.slice(0,10)===today;});
  var todayTotal=todaySales.reduce(function(a,s){return a+s.total;},0);
  var todayCount=todaySales.length;
  var avgSale=todayCount?todayTotal/todayCount:0;
  var lowStock=bizProducts.filter(function(p){return p.stock<=5;}).length;

  // top products by sold qty today
  var qtyByProd={};
  todaySales.forEach(function(s){
    (s.items||[]).forEach(function(it){
      qtyByProd[it.name]=(qtyByProd[it.name]||0)+it.qty;
    });
  });
  var topProds=Object.keys(qtyByProd).map(function(k){return {n:k,q:qtyByProd[k]};}).sort(function(a,b){return b.q-a.q;}).slice(0,5);

  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Dashboard","Guriga")+"</div>";
  h+="<div class=\"phS\">"+esc(BIZ.name)+" &middot; "+T("Today: ","Maanta: ")+new Date().toLocaleDateString()+"</div></div>";
  h+="<div class=\"phA\"><button class=\"btn btnP\" onclick=\"goTo('pos')\">&#128722; "+T("Start selling","Bilow iib")+"</button></div></div>";

  h+="<div class=\"kG\">";
  h+=kpi(T("Today's sales","Iibka maanta"),money(todayTotal),"#1a6ef5",todayCount+" "+T("transactions","macaamil"));
  h+=kpi(T("Avg ticket","Celcelis"),money(avgSale),"#36b37e",null);
  h+=kpi(T("Products","Alaabta"),bizProducts.length,"#6554c0",null);
  h+=kpi(T("Low stock","Kayd hooseeya"),lowStock,lowStock>0?"#bf2600":"#36b37e",lowStock>0?T("Re-order soon","Dib u soo dalbo"):T("All stocked","Buuxa"));
  h+="</div>";

  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#11088; "+T("Top sellers today","Alaabta iibka badan maanta")+"</div></div><div class=\"bB\">";
  if(!topProds.length){h+="<div class=\"empty\"><div class=\"emIc\">&#128181;</div>"+T("No sales yet today","Iib lama qaadin maanta")+"</div>";}
  else{
    topProds.forEach(function(p,i){
      h+="<div style=\"display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid #f0f2f5\">";
      h+="<div style=\"width:24px;height:24px;border-radius:50%;background:#1a6ef5;color:#fff;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700\">"+(i+1)+"</div>";
      h+="<div style=\"flex:1\">"+esc(p.n)+"</div>";
      h+="<div class=\"bdg bg\">"+p.q+" "+T("sold","la iibiyay")+"</div></div>";
    });
  }
  h+="</div></div>";
  return h;
};

function kpi(l,v,c,sub){
  return "<div class=\"kC\"><div class=\"kL\">"+l+"</div><div class=\"kV\" style=\"color:"+(c||"#0a1628")+"\">"+v+"</div>"+(sub?"<div class=\"kSb\">"+sub+"</div>":"")+"</div>";
}

// ============================================================
//  PAGE: POS TERMINAL
// ============================================================
PAGES.pos=function(){
  var cats=["all"].concat(_uniqueCats());
  var h="<div class=\"posWrap\">";
  // LEFT: products + search
  h+="<div class=\"posLeft\">";
  h+="<div class=\"posSearch\">";
  h+="<input type=\"text\" id=\"posQ\" oninput=\"_filterProducts()\" placeholder=\""+T("Search products...","Raadi alaab...")+"\">";
  if(_bizUsesBarcode()){
    h+="<input type=\"text\" id=\"posBC\" onkeydown=\"if(event.key==='Enter')_scanBarcode(this)\" placeholder=\""+T("Scan / type barcode...","Garaaco / qor barcode...")+"\" style=\"flex:1;min-width:160px;font-family:monospace\">";
  }
  cats.forEach(function(c){
    var on=CAT_FILTER===c?" on":"";
    h+="<button class=\"catChip"+on+"\" onclick=\"CAT_FILTER='"+esc(c)+"';renderPage('pos')\">"+(c==="all"?T("All","Dhamaan"):esc(c))+"</button>";
  });
  h+="</div>";
  h+="<div class=\"prodGrid\" id=\"prodGrid\">"+_renderProductCards()+"</div>";
  h+="</div>";
  // RIGHT: cart
  h+="<div class=\"posRight\" id=\"posCart\">";
  h+="<div class=\"posCartH\" onclick=\"_toggleCart()\">";
  h+="<div class=\"ttl\">&#128722; "+T("Cart","Bacda")+" <span id=\"cartCt\">("+CART.length+")</span></div>";
  h+="<button class=\"clr\" onclick=\"event.stopPropagation();_clearCart()\">&#10005; "+T("Clear","Nadiifi")+"</button>";
  h+="</div>";
  // Restaurant/Cafe/Bar: table + order type pickers right above the cart list
  if(_bizUsesTables()){
    h+="<div style=\"padding:10px 14px;background:#fff7d6;border-bottom:1px solid #ffe7a3;display:grid;grid-template-columns:1fr 1fr;gap:8px\">";
    h+="<div><label style=\"font-size:9px;margin-bottom:3px\">"+T("Table","Miis")+"</label>";
    h+="<input type=\"text\" id=\"posTbl\" value=\""+esc(TABLE_NO)+"\" oninput=\"TABLE_NO=this.value\" placeholder=\"#"+T("e.g. 5","ts. 5")+"\" style=\"padding:5px 8px;font-size:12px\"></div>";
    h+="<div><label style=\"font-size:9px;margin-bottom:3px\">"+T("Order type","Nooca dalbka")+"</label>";
    h+="<select id=\"posOT\" onchange=\"ORDER_TYPE=this.value\" style=\"padding:5px 8px;font-size:12px\">"+
      [["Dine-in",T("Dine-in","Halkan ku cun")],["Takeaway",T("Takeaway","Qaado")],["Delivery",T("Delivery","Geyn")]]
        .map(function(o){return "<option value=\""+o[0]+"\""+(ORDER_TYPE===o[0]?" selected":"")+">"+o[1]+"</option>";}).join("")+
      "</select></div>";
    h+="</div>";
  }
  h+="<div class=\"posCartList\" id=\"cartList\">"+_renderCart()+"</div>";
  h+=_renderCartSummary();
  h+="<div class=\"posCheckout\"><button class=\"btn btnG\" onclick=\"checkout()\">&#128181; "+T("Checkout","Bixi")+"</button></div>";
  h+="</div></div>";
  return h;
};
// Retail barcode scan: look up by sku/barcode (case-insensitive). If found, add to cart.
function _scanBarcode(input){
  var code=(input.value||"").trim();if(!code)return;
  var p=forBiz(PRODUCTS).find(function(x){return ((x.sku||"")+"").toLowerCase()===code.toLowerCase()||((x.barcode||"")+"").toLowerCase()===code.toLowerCase();});
  if(!p){toast(T("Not found: ","Lama helin: ")+code);input.select();return;}
  if(p.stock<=0){toast(T("Out of stock","Kaydka ma jiro"));return;}
  addToCart(p.id);
  input.value="";input.focus();
}
function _uniqueCats(){var s={};forBiz(PRODUCTS).forEach(function(p){if(p.cat)s[p.cat]=1;});return Object.keys(s).sort();}
function _filterProducts(){
  $("prodGrid").innerHTML=_renderProductCards();
}
function _renderProductCards(){
  var q=($("posQ")&&$("posQ").value||"").toLowerCase();
  var list=forBiz(PRODUCTS).filter(function(p){
    if(CAT_FILTER!=="all"&&p.cat!==CAT_FILTER)return false;
    if(q&&p.name.toLowerCase().indexOf(q)<0&&(p.cat||"").toLowerCase().indexOf(q)<0)return false;
    return true;
  });
  if(!list.length)return "<div class=\"empty\" style=\"grid-column:1/-1\"><div class=\"emIc\">&#128269;</div>"+T("No products match","Wax aan u dhigma ma jiraan")+"</div>";
  return list.map(function(p){
    var out=p.stock<=0?" out":"";
    var stkCls=p.stock<=5?" low":"";
    return "<div class=\"prodC"+out+"\" onclick=\""+(p.stock>0?"addToCart('"+p.id+"')":"toast('"+T("Out of stock","Kaydka ma jiro")+"')")+"\">"+
      "<div class=\"pIc\">"+(p.icon||"&#128230;")+"</div>"+
      "<div class=\"pCt\">"+esc(p.cat||"")+"</div>"+
      "<div class=\"pNm\">"+esc(p.name)+"</div>"+
      "<div class=\"pPr\">"+money(p.price)+"</div>"+
      "<div class=\"pStk"+stkCls+"\">"+T("Stock: ","Kayd: ")+p.stock+"</div>"+
    "</div>";
  }).join("");
}
function addToCart(pid){
  var p=PRODUCTS.find(function(x){return x.id===pid;});if(!p||p.stock<=0)return;
  var line=CART.find(function(c){return c.id===pid;});
  if(line){
    if(line.qty<p.stock)line.qty++;
    else{toast(T("Not enough stock","Kayd ma fillin"));return;}
  } else {
    CART.push({id:p.id,name:p.name,price:p.price,qty:1,maxStock:p.stock});
  }
  _refreshCart();
}
function changeQty(pid,delta){
  var line=CART.find(function(c){return c.id===pid;});if(!line)return;
  var p=PRODUCTS.find(function(x){return x.id===pid;});
  line.qty+=delta;
  if(line.qty<=0){CART=CART.filter(function(c){return c.id!==pid;});}
  else if(p&&line.qty>p.stock){line.qty=p.stock;toast(T("Max stock reached","Kaydka ugu badan la gaadhay"));}
  _refreshCart();
}
function removeFromCart(pid){CART=CART.filter(function(c){return c.id!==pid;});_refreshCart();}
async function _clearCart(){if(CART.length&&!await igAsk(T("Clear the cart?","Bacda nadiifi?")))return;CART=[];_refreshCart();}
function _toggleCart(){var c=$("posCart");if(c)c.classList.toggle("open");}
function _refreshCart(){
  var cl=$("cartList");if(cl)cl.innerHTML=_renderCart();
  var ct=$("cartCt");if(ct)ct.textContent="("+CART.length+")";
  var sum=document.querySelector(".posSum");
  if(sum)sum.outerHTML=_renderCartSummary();
}
function _renderCart(){
  if(!CART.length)return "<div class=\"empty\"><div class=\"emIc\">&#128722;</div>"+T("Cart is empty","Bacda waa madhan")+"</div>";
  return CART.map(function(c){
    return "<div class=\"cartRow\">"+
      "<div style=\"flex:1;min-width:0\"><div class=\"cNm\">"+esc(c.name)+"</div><div class=\"cPr\">"+money(c.price)+" × "+c.qty+"</div></div>"+
      "<button class=\"qtyBtn\" onclick=\"changeQty('"+c.id+"',-1)\">-</button>"+
      "<span class=\"qtyVal\">"+c.qty+"</span>"+
      "<button class=\"qtyBtn\" onclick=\"changeQty('"+c.id+"',1)\">+</button>"+
      "<div class=\"cartTot\">"+money(c.price*c.qty)+"</div>"+
      "<button class=\"cartRm\" onclick=\"removeFromCart('"+c.id+"')\">&#128465;</button>"+
    "</div>";
  }).join("");
}
function _cartTotals(){
  var sub=CART.reduce(function(a,c){return a+c.price*c.qty;},0);
  var tax=sub*((BIZ.tax||0)/100);
  return {sub:sub,tax:tax,tot:sub+tax,items:CART.reduce(function(a,c){return a+c.qty;},0)};
}
function _renderCartSummary(){
  var t=_cartTotals();
  var h="<div class=\"posSum\">";
  h+="<div class=\"sumRow\"><span>"+T("Items","Tirada")+"</span><span>"+t.items+"</span></div>";
  h+="<div class=\"sumRow\"><span>"+T("Subtotal","Wadarta")+"</span><span>"+money(t.sub)+"</span></div>";
  if(BIZ.tax>0)h+="<div class=\"sumRow\"><span>"+T("Tax","Canshuur")+" ("+BIZ.tax+"%)</span><span>"+money(t.tax)+"</span></div>";
  h+="<div class=\"sumRow tot\"><span>"+T("Total","Wadarta guud")+"</span><span>"+money(t.tot)+"</span></div>";
  h+="</div>";
  return h;
}
function checkout(){
  if(!CART.length){toast(T("Add items first","Marka hore alaab ku dar"));return;}
  var t=_cartTotals();
  var sale={
    id:"s"+Date.now(),
    bizId:CURRENT_BIZ_ID,
    date:new Date().toISOString(),
    cashier:CURRENT_USER.name,
    items:CART.map(function(c){return {id:c.id,name:c.name,price:c.price,qty:c.qty};}),
    subtotal:t.sub,tax:t.tax,total:t.tot,
    currency:CURRENCY,
    bizType:BIZ.type,
    tableNo:_bizUsesTables()?TABLE_NO:"",
    orderType:_bizUsesTables()?ORDER_TYPE:""
  };
  // Decrement stock
  CART.forEach(function(c){
    var p=PRODUCTS.find(function(x){return x.id===c.id;});
    if(p){p.stock=Math.max(0,p.stock-c.qty);}
  });
  SALES.unshift(sale);
  _save("pos_prod",PRODUCTS);
  _save("pos_sales",SALES);
  _showReceipt(sale);
  CART=[];
  TABLE_NO="";   // reset for next order
  _refreshCart();
}

function _showReceipt(sale){
  var w=42;
  function center(s){var p=Math.max(0,Math.floor((w-s.length)/2));return Array(p+1).join(" ")+s;}
  function line(a,b){var p=Math.max(1,w-a.length-b.length);return a+Array(p+1).join(" ")+b;}
  var h="";
  h+=center(BIZ.name||"Casri POS")+"\n";
  if(BIZ.addr)h+=center(BIZ.addr)+"\n";
  if(BIZ.phone)h+=center(BIZ.phone)+"\n";
  h+="-".repeat(w)+"\n";
  h+=line(T("Receipt #","Kaadhka #")+sale.id.slice(-6), new Date(sale.date).toLocaleString())+"\n";
  h+=line(T("Cashier","Iibiyaha"),sale.cashier)+"\n";
  if(sale.tableNo)h+=line(T("Table","Miis"),"#"+sale.tableNo)+"\n";
  if(sale.orderType)h+=line(T("Order","Dalbka"),sale.orderType)+"\n";
  h+="-".repeat(w)+"\n";
  sale.items.forEach(function(it){
    h+=line(it.name.slice(0,24)+" x"+it.qty,money(it.price*it.qty))+"\n";
  });
  h+="-".repeat(w)+"\n";
  h+=line(T("Subtotal","Wadarta"),money(sale.subtotal))+"\n";
  if(sale.tax>0)h+=line(T("Tax","Canshuur"),money(sale.tax))+"\n";
  h+=line(T("TOTAL","WADARTA"),money(sale.total))+"\n";
  h+="\n"+center(T("Thank you!","Mahadsanid!"))+"\n";
  $("rec_body").textContent=h;
  openM("M_rec");
}
function printReceipt(){
  var w=window.open("","_blank","width=320,height=600");
  if(!w){toast("Pop-up blocked");return;}
  w.document.write("<pre style=\"font-family:monospace;font-size:11px;line-height:1.6\">"+esc($("rec_body").textContent)+"</pre>");
  w.document.close();w.focus();w.print();
}

// ============================================================
//  PAGE: PRODUCTS
// ============================================================
var EDIT_PROD=null;
PAGES.products=function(){
  var bizProducts=forBiz(PRODUCTS);
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Products","Alaabta")+"</div><div class=\"phS\">"+esc(BIZ.name)+" &middot; "+bizProducts.length+" "+T("items","alaab")+"</div></div>";
  h+="<div class=\"phA\"><button class=\"btn btnP\" onclick=\"openAddProduct()\">+ "+T("Add product","Ku dar alaab")+"</button></div></div>";
  h+="<div class=\"box\"><table><thead><tr><th>"+T("Product","Alaabta")+"</th><th>"+T("Category","Qaybta")+"</th><th>"+T("Price","Qiimaha")+"</th><th>"+T("Stock","Kayd")+"</th><th></th></tr></thead><tbody>";
  if(!bizProducts.length){h+="<tr><td colspan=\"5\"><div class=\"empty\"><div class=\"emIc\">&#128230;</div>"+T("No products yet","Alaab ma jirto weli")+"</div></td></tr>";}
  else{
    bizProducts.forEach(function(p){
      var stkBdg=p.stock<=0?"br":p.stock<=5?"ba":"bg";
      h+="<tr><td><strong>"+(p.icon||"&#128230;")+" "+esc(p.name)+"</strong></td>";
      h+="<td><span class=\"bdg bgr\">"+esc(p.cat||"-")+"</span></td>";
      h+="<td><strong>"+money(p.price)+"</strong></td>";
      h+="<td><span class=\"bdg "+stkBdg+"\">"+p.stock+"</span></td>";
      h+="<td style=\"text-align:right;white-space:nowrap\">";
      h+="<button class=\"btn\" onclick=\"openEditProduct('"+p.id+"')\">&#9998;</button> ";
      h+="<button class=\"btn btnR\" onclick=\"delProduct('"+p.id+"')\">&#10005;</button>";
      h+="</td></tr>";
    });
  }
  h+="</tbody></table></div>";
  return h;
};
function openAddProduct(){
  EDIT_PROD=null;
  ["mp_nm","mp_cat","mp_pr","mp_stk","mp_ic","mp_sku","mp_bc"].forEach(function(id){var e=$(id);if(e)e.value="";});
  // SKU + barcode fields are only relevant for retail; hide otherwise
  var rr=$("mp_retail_row");if(rr)rr.style.display=_bizUsesBarcode()?"grid":"none";
  $("M_prod_t").textContent=T("Add product","Ku dar alaab");
  openM("M_prod");
}
function openEditProduct(pid){
  var p=PRODUCTS.find(function(x){return x.id===pid;});if(!p)return;
  EDIT_PROD=pid;
  $("mp_nm").value=p.name;
  $("mp_cat").value=p.cat||"";
  $("mp_pr").value=p.price;
  $("mp_stk").value=p.stock;
  $("mp_ic").value=p.icon||"";
  if($("mp_sku"))$("mp_sku").value=p.sku||"";
  if($("mp_bc"))$("mp_bc").value=p.barcode||"";
  var rr=$("mp_retail_row");if(rr)rr.style.display=(_bizUsesBarcode()||p.sku||p.barcode)?"grid":"none";
  $("M_prod_t").textContent=T("Edit product","Wax ka beddel alaab");
  openM("M_prod");
}
function saveProduct(){
  var nm=$("mp_nm").value.trim();if(!nm){toast(T("Enter product name","Gali magaca alaabta"));return;}
  var pr=parseFloat($("mp_pr").value);if(isNaN(pr)||pr<0){toast(T("Invalid price","Qiimaha khalad"));return;}
  var stk=parseInt($("mp_stk").value);if(isNaN(stk)||stk<0)stk=0;
  var sku=$("mp_sku")?$("mp_sku").value.trim():"";
  var bc=$("mp_bc")?$("mp_bc").value.trim():"";
  if(EDIT_PROD){
    var p=PRODUCTS.find(function(x){return x.id===EDIT_PROD;});
    if(p){p.name=nm;p.cat=$("mp_cat").value.trim();p.price=pr;p.stock=stk;p.icon=$("mp_ic").value.trim();p.sku=sku;p.barcode=bc;}
  } else {
    PRODUCTS.push({id:"p"+Date.now(),bizId:CURRENT_BIZ_ID,name:nm,cat:$("mp_cat").value.trim(),price:pr,stock:stk,icon:$("mp_ic").value.trim()||"📦",sku:sku,barcode:bc});
  }
  _save("pos_prod",PRODUCTS);
  closeM("M_prod");
  toast(EDIT_PROD?T("Updated","La cusbooneysiiyay"):T("Added","Lagu daray"));
  renderPage("products");
}
async function delProduct(pid){
  var p=PRODUCTS.find(function(x){return x.id===pid&&x.bizId===CURRENT_BIZ_ID;});if(!p)return;
  if(!await igAsk(T("Delete ","Tirtir ")+p.name+"?"))return;
  PRODUCTS=PRODUCTS.filter(function(x){return x.id!==pid;});
  _save("pos_prod",PRODUCTS);
  renderPage("products");
  toast(T("Deleted","La tirtiray"));
}

// ============================================================
//  PAGE: SALES HISTORY
// ============================================================
PAGES.sales=function(){
  var bizSales=forBiz(SALES);
  var showTable=_bizUsesTables();
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Sales History","Taariikhda Iibka")+"</div><div class=\"phS\">"+esc(BIZ.name)+" &middot; "+bizSales.length+" "+T("transactions","macaamil")+"</div></div></div>";
  var head="<th>"+T("Receipt","Kaadh")+"</th><th>"+T("Date","Taariikh")+"</th>";
  if(showTable)head+="<th>"+T("Table / Order","Miis / Dalbka")+"</th>";
  head+="<th>"+T("Items","Alaab")+"</th><th>"+T("Cashier","Iibiyaha")+"</th><th>"+T("Total","Wadarta")+"</th><th></th>";
  h+="<div class=\"box\"><table><thead><tr>"+head+"</tr></thead><tbody>";
  var colspan=showTable?7:6;
  if(!bizSales.length){h+="<tr><td colspan=\""+colspan+"\"><div class=\"empty\"><div class=\"emIc\">&#128181;</div>"+T("No sales yet","Iib lama jirin weli")+"</div></td></tr>";}
  else{
    bizSales.slice(0,200).forEach(function(s){
      var itemCt=(s.items||[]).reduce(function(a,it){return a+it.qty;},0);
      h+="<tr><td><strong>#"+esc(s.id.slice(-6))+"</strong></td>";
      h+="<td>"+new Date(s.date).toLocaleString()+"</td>";
      if(showTable){
        var tbl=s.tableNo?"#"+esc(s.tableNo):"-";
        var ot=s.orderType||"-";
        h+="<td><div style=\"font-weight:700\">"+tbl+"</div><div style=\"font-size:10px;color:#999\">"+esc(ot)+"</div></td>";
      }
      h+="<td>"+itemCt+"</td>";
      h+="<td>"+esc(s.cashier||"-")+"</td>";
      h+="<td><strong style=\"color:#1a6ef5\">"+money(s.total)+"</strong></td>";
      h+="<td><button class=\"btn\" onclick=\"_viewSale('"+s.id+"')\">&#128424;</button></td></tr>";
    });
  }
  h+="</tbody></table></div>";
  return h;
};
function _viewSale(sid){var s=SALES.find(function(x){return x.id===sid&&x.bizId===CURRENT_BIZ_ID;});if(s)_showReceipt(s);}

// ============================================================
//  PAGE: REPORTS
// ============================================================
PAGES.reports=function(){
  var bizSales=forBiz(SALES);
  var bizProducts=forBiz(PRODUCTS);
  var byDay={},byProd={};
  bizSales.forEach(function(s){
    var d=s.date.slice(0,10);
    byDay[d]=(byDay[d]||0)+s.total;
    (s.items||[]).forEach(function(it){
      var k=it.name;
      if(!byProd[k])byProd[k]={qty:0,rev:0};
      byProd[k].qty+=it.qty;byProd[k].rev+=it.price*it.qty;
    });
  });
  var days=Object.keys(byDay).sort().slice(-14);
  var topProds=Object.keys(byProd).map(function(k){return {n:k,q:byProd[k].qty,r:byProd[k].rev};}).sort(function(a,b){return b.r-a.r;}).slice(0,10);
  var totalRev=bizSales.reduce(function(a,s){return a+s.total;},0);

  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Reports","Warbixinno")+"</div><div class=\"phS\">"+esc(BIZ.name)+" &middot; "+T("Sales overview","Guudmar iibka")+"</div></div></div>";
  h+="<div class=\"kG\">";
  h+=kpi(T("Lifetime sales","Iibka guud"),money(totalRev),"#1a6ef5",bizSales.length+" "+T("sales","iib"));
  h+=kpi(T("Avg sale","Celcelis"),money(bizSales.length?totalRev/bizSales.length:0),"#36b37e",null);
  h+=kpi(T("Products sold","Alaab la iibiyay"),topProds.reduce(function(a,p){return a+p.q;},0),"#6554c0",null);
  h+=kpi(T("SKUs","SKU"),bizProducts.length,"#ff991f",null);
  h+="</div>";
  // Daily chart
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#128202; "+T("Last 14 days","14-kii maalmood ee dambeeyay")+"</div></div><div class=\"bB\">";
  if(!days.length){h+="<div class=\"empty\">"+T("No data yet","Xog ma jirto weli")+"</div>";}
  else{
    var max=Math.max.apply(null,days.map(function(d){return byDay[d];}));
    h+="<div style=\"display:flex;align-items:end;gap:6px;height:140px;padding-top:10px\">";
    days.forEach(function(d){
      var pct=Math.round(byDay[d]/max*100);
      h+="<div style=\"flex:1;display:flex;flex-direction:column;align-items:center;gap:4px\" title=\""+d+" — "+money(byDay[d])+"\">";
      h+="<div style=\"flex:1;display:flex;align-items:end;width:100%\"><div style=\"width:100%;background:#1a6ef5;border-radius:4px 4px 0 0;height:"+pct+"%;min-height:2px\"></div></div>";
      h+="<div style=\"font-size:9px;color:#999\">"+d.slice(8,10)+"</div></div>";
    });
    h+="</div>";
  }
  h+="</div></div>";
  // Top products
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#11088; "+T("Top sellers (all time)","Alaabta iibka badan")+"</div></div><div class=\"bB\">";
  if(!topProds.length){h+="<div class=\"empty\">"+T("No data yet","Xog ma jirto weli")+"</div>";}
  else{
    topProds.forEach(function(p,i){
      h+="<div style=\"display:flex;align-items:center;gap:10px;padding:7px 0;border-bottom:1px solid #f0f2f5\">";
      h+="<div style=\"width:22px;color:#999;font-size:11px;font-weight:700\">#"+(i+1)+"</div>";
      h+="<div style=\"flex:1\">"+esc(p.n)+"</div>";
      h+="<div class=\"bdg bgr\" style=\"margin-right:6px\">"+p.q+" "+T("sold","iib")+"</div>";
      h+="<div style=\"font-weight:700;color:#1a6ef5;min-width:80px;text-align:right\">"+money(p.r)+"</div></div>";
    });
  }
  h+="</div></div>";
  return h;
};

// ============================================================
//  PAGE: BUSINESSES (admin only) — manage multiple Casri POS shops
// ============================================================
var EDIT_BIZ=null;
PAGES.businesses=function(){
  if(!isSuperAdmin())return "<div class=\"empty\">"+T("Super-admin only","Maamulaha guud kaliya")+"</div>";
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Businesses","Ganacsiyada")+"</div><div class=\"phS\">"+BIZ_LIST.length+" "+T("registered","la diiwaangeliyay")+"</div></div>";
  h+="<div class=\"phA\"><button class=\"btn btnP\" onclick=\"openAddBiz()\">+ "+T("Add business","Ku dar ganacsi")+"</button></div></div>";
  h+="<div class=\"box\"><table><thead><tr><th>"+T("Name","Magaca")+"</th><th>"+T("Type","Nooca")+"</th><th>"+T("Currency","Lacagta")+"</th><th>"+T("Admins","Maamulayaal")+"</th><th>"+T("Products","Alaab")+"</th><th>"+T("Sales","Iib")+"</th><th></th></tr></thead><tbody>";
  BIZ_LIST.forEach(function(b){
    var btype=BIZ_TYPES.find(function(x){return x.k===b.type;});
    var bIc=btype?btype.ic:"🏢";
    var bLbl=btype?T(btype.en,btype.so):b.type;
    var pCt=PRODUCTS.filter(function(p){return p.bizId===b.id;}).length;
    var sCt=SALES.filter(function(s){return s.bizId===b.id;}).length;
    var aCt=ACCOUNTS.filter(function(a){return a.role==="admin"&&a.bizId===b.id;}).length;
    var active=b.id===CURRENT_BIZ_ID;
    h+="<tr"+(active?" style=\"background:#eff6ff\"":"")+">";
    h+="<td><strong>"+(active?"&#9679; ":"")+esc(b.name)+"</strong>"+(active?" <span class=\"bdg bb\" style=\"margin-left:6px\">"+T("Active","Firfircoon")+"</span>":"")+"</td>";
    h+="<td>"+bIc+" "+esc(bLbl)+"</td>";
    h+="<td>"+esc(b.currency||"USD")+"</td>";
    h+="<td><span class=\"bdg "+(aCt?"bg":"bgr")+"\">"+aCt+"</span></td>";
    h+="<td>"+pCt+"</td><td>"+sCt+"</td>";
    h+="<td style=\"text-align:right;white-space:nowrap\">";
    if(!active)h+="<button class=\"btn\" onclick=\"switchBiz('"+b.id+"')\" title=\""+T("Switch to","U wareeji ")+esc(b.name)+"\">&#8634;</button> ";
    h+="<button class=\"btn\" onclick=\"openAddBizAdmin('"+b.id+"')\" title=\""+T("Add admin for this business","Ku dar maamule ganacsigan")+"\">&#128100;+</button> ";
    h+="<button class=\"btn\" onclick=\"openEditBiz('"+b.id+"')\">&#9998;</button> ";
    if(BIZ_LIST.length>1)h+="<button class=\"btn btnR\" onclick=\"delBiz('"+b.id+"')\">&#10005;</button>";
    h+="</td></tr>";
  });
  h+="</tbody></table></div>";
  // Help banner — explains the per-business admin login workflow
  h+="<div style=\"background:#ebf3ff;border-radius:8px;padding:13px;border:1px solid #c7d7ff;font-size:11px;color:#0052cc;margin-bottom:11px\">";
  h+="<strong>&#128161; "+T("How multi-business works","Sida ganacsiyada badan ay u shaqeeyaan")+"</strong><br>"+
     T("Each business has its own products, sales, type, and settings. As super-admin, use the sidebar dropdown to switch between them.",
       "Ganacsi kasta wuxuu leeyahay alaabtiisa, iibkiisa, nooca, iyo habayntiisa gaarka ah. Isticmaal liiska sare si aad u wareejiso.");
  h+="</div>";
  // Workflow banner — explains how per-business admins log in
  h+="<div style=\"background:#fff7d6;border-radius:8px;padding:13px;border:1px solid #ffe7a3;font-size:11px;color:#974f0c\">";
  h+="<strong>&#128272; "+T("How other businesses sign in","Sida ganacsiyada kale ay u galaan")+"</strong><br>";
  h+=T("Every business uses the SAME login page (this URL). Click ","Ganacsi kastaa wuxuu isticmaalaa SHIDA bog gelitaanka. Riix ")+
     "&#128100;+ "+T("on a business row to create its admin. Share the username + password you choose with them.","ka dib safka ganacsiga si aad ugu samayso maamule. La wadaag macluumaadka aad samaysid.")+"<br><br>"+
     T("When they sign in, the system reads their account and takes them straight to their business — no \"switch business\" step needed. They only see their business's data, not yours or anyone else's.",
       "Markay galaan, nidaamku wuxuu akhriyaa akoonkooda oo si toos ah ayuu u geeyaa ganacsigooda — lama u baahna wareejin. Waxay arkaan oo kaliya xogta ganacsigooda.");
  h+="</div>";
  return h;
};
function openAddBiz(){
  EDIT_BIZ=null;
  $("M_biz_t").textContent=T("Add business","Ku dar ganacsi");
  $("mb_nm").value="";
  $("mb_type").value="shop";
  $("mb_ccy").value="USD";
  $("mb_addr").value="";
  $("mb_ph").value="";
  $("mb_tax").value=0;
  openM("M_biz");
}
function openEditBiz(bid){
  var b=BIZ_LIST.find(function(x){return x.id===bid;});if(!b)return;
  EDIT_BIZ=bid;
  $("M_biz_t").textContent=T("Edit business","Wax ka beddel ganacsi");
  $("mb_nm").value=b.name||"";
  $("mb_type").value=b.type||"shop";
  $("mb_ccy").value=b.currency||"USD";
  $("mb_addr").value=b.addr||"";
  $("mb_ph").value=b.phone||"";
  $("mb_tax").value=b.tax||0;
  openM("M_biz");
}
function saveBiz(){
  var nm=$("mb_nm").value.trim();if(!nm){toast(T("Enter business name","Gali magaca"));return;}
  var rec={
    name:nm,
    type:$("mb_type").value,
    currency:$("mb_ccy").value,
    addr:$("mb_addr").value.trim(),
    phone:$("mb_ph").value.trim(),
    tax:parseFloat($("mb_tax").value)||0
  };
  if(EDIT_BIZ){
    var b=BIZ_LIST.find(function(x){return x.id===EDIT_BIZ;});
    if(b)Object.assign(b,rec);
  } else {
    rec.id="b"+Date.now();
    BIZ_LIST.push(rec);
  }
  _saveBiz();
  closeM("M_biz");
  toast(EDIT_BIZ?T("Updated","La cusbooneysiiyay"):T("Business added","La sameeyay"));
  buildNav();
  renderPage("businesses");
}
// Quick-create a per-business admin from the Businesses page.
// The new account is scoped to bid — they can only log into that one business.
async function openAddBizAdmin(bid){
  var b=BIZ_LIST.find(function(x){return x.id===bid;});if(!b)return;
  var name=await igAskText(T("Full name for "+b.name+" admin","Magaca buuxa ee maamulaha "+b.name));
  if(!name)return;
  var user=await igAskText(T("Username (used to sign in)","Magaca isticmaale"));
  if(!user)return;
  if(ACCOUNTS.find(function(a){return a.username.toLowerCase()===user.toLowerCase();})){toast(T("Username already taken","Magaca la qaatay"));return;}
  var pass=await igAskText(T("Password","Sirta"));
  if(!pass)return;
  ACCOUNTS.push({id:"a"+Date.now(),name:name,username:user,password:pass,role:"admin",bizId:bid,active:true});
  _save("pos_acc",ACCOUNTS);
  renderPage("businesses");
  // Show the credentials clearly so the super-admin can share them — and
  // explain the workflow so it's obvious how the new admin logs in.
  igAlert(
    T("Admin created for "+b.name+"!\n\n","Maamule loo abuuray "+b.name+"!\n\n")+
    T("Share these login details with the "+b.name+" admin:\n\n","La wadaag macluumaadkan maamulaha "+b.name+":\n\n")+
    "  "+T("Username","Magaca isticmaale")+": "+user+"\n"+
    "  "+T("Password","Sirta")+":  "+pass+"\n\n"+
    T("They open this same URL, type those credentials on the login screen, and the system automatically takes them to "+b.name+" only — no \"switch business\" step needed.",
      "Waxay furayaan isla URL-kan, qoraan macluumaadka isticmaalka, oo nidaamku si toos ah ayuu u geeyaa "+b.name+" oo kaliya — lama u baahna in la wareejiyo.")
  );
}
async function delBiz(bid){
  if(BIZ_LIST.length<=1){toast(T("Keep at least one business","Hayso ugu yaraan hal ganacsi"));return;}
  var b=BIZ_LIST.find(function(x){return x.id===bid;});if(!b)return;
  var pCt=PRODUCTS.filter(function(p){return p.bizId===bid;}).length;
  var sCt=SALES.filter(function(s){return s.bizId===bid;}).length;
  if(!await igAsk(T("Delete \""+b.name+"\"? This also removes its "+pCt+" product(s) and "+sCt+" sale(s). Cannot be undone.",
              "Tirtir \""+b.name+"\"? Tan waxay sidoo kale tirtirtaa "+pCt+" alaab iyo "+sCt+" iib.")))return;
  BIZ_LIST=BIZ_LIST.filter(function(x){return x.id!==bid;});
  PRODUCTS=PRODUCTS.filter(function(p){return p.bizId!==bid;});
  SALES=SALES.filter(function(s){return s.bizId!==bid;});
  if(CURRENT_BIZ_ID===bid)CURRENT_BIZ_ID=BIZ_LIST[0].id;
  _saveBiz();_save("pos_prod",PRODUCTS);_save("pos_sales",SALES);
  buildNav();renderUser();renderPage("businesses");
  toast(T("Deleted","La tirtiray"));
}

// ============================================================
//  PAGE: USERS (admin only)
// ============================================================
PAGES.users=function(){
  if(CURRENT_USER.role!=="admin")return "<div class=\"empty\">"+T("Admin only","Maamulaha kaliya")+"</div>";
  // Super-admin sees ALL accounts across every business; per-business admin
  // only sees accounts for their own business (plus themselves).
  // A business admin sees ONLY their own business's accounts. The old filter also
  // let through every account with a blank bizId — which meant each business admin
  // could see the master super-admin row AND reveal its password with the eye
  // button. Never show unscoped accounts to a scoped admin.
  var visible=isSuperAdmin()?ACCOUNTS:ACCOUNTS.filter(function(a){return !!a.bizId&&a.bizId===CURRENT_USER.bizId;});
  var scopeNote=isSuperAdmin()?T("All businesses","Dhammaan ganacsiyada"):esc(BIZ.name);
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Users","Isticmaalayaal")+"</div><div class=\"phS\">"+scopeNote+" &middot; "+visible.length+" "+T("accounts","akoon")+"</div></div>";
  h+="<div class=\"phA\"><button class=\"btn btnP\" onclick=\"_newAccount()\">+ "+T("Add user","Ku dar")+"</button></div></div>";
  h+="<div class=\"box\"><table><thead><tr><th>"+T("Name","Magaca")+"</th><th>"+T("Username","Isticmaale")+"</th><th>"+T("Password","Sirta")+"</th><th>"+T("Role","Doorka")+"</th><th>"+T("Business","Ganacsi")+"</th><th></th></tr></thead><tbody>";
  visible.forEach(function(a){
    var b=a.bizId?BIZ_LIST.find(function(x){return x.id===a.bizId;}):null;
    // Flag accidental super-admins: if any non-admin account or any non-original admin
    // ended up with empty bizId, surface a warning so it's easy to fix.
    var isOrphan=!a.bizId&&a.username.toLowerCase()!=="admin";
    var bLbl=b?esc(b.name):(isOrphan?"<span style=\"color:#bf2600\">&#9888; "+T("Unscoped — fix me","Lama qeexin — saxa")+"</span>":"<span style=\"color:#1a6ef5\">"+T("All (super-admin)","Dhammaan")+"</span>");
    h+="<tr"+(isOrphan?" style=\"background:#fff7d6\"":"")+"><td><strong>"+esc(a.name)+"</strong></td>";
    h+="<td>"+esc(a.username)+"</td>";
    h+="<td><span id=\"pw_"+a.id+"\" style=\"font-family:monospace\">••••••</span> <button class=\"btn\" style=\"padding:2px 6px;font-size:10px\" onclick=\"_togglePw('"+a.id+"','"+esc(a.password)+"')\">&#128065;</button></td>";
    h+="<td><span class=\"bdg "+(a.role==="admin"?"bb":"bg")+"\">"+a.role+"</span></td>";
    h+="<td>"+bLbl+"</td>";
    h+="<td style=\"text-align:right;white-space:nowrap\">";
    if(isSuperAdmin()&&a.username.toLowerCase()!=="admin"){
      h+="<button class=\"btn\" onclick=\"reassignAccount('"+a.id+"')\" title=\""+T("Move to business","U wareeji ganacsi")+"\">&#127970;</button> ";
    }
    h+=(a.id!==CURRENT_USER.id?"<button class=\"btn btnR\" onclick=\"_delAcc('"+a.id+"')\">&#10005;</button>":"-");
    h+="</td></tr>";
  });
  h+="</tbody></table></div>";
  return h;
};
function _togglePw(id,pw){var el=$("pw_"+id);if(!el)return;if(el.getAttribute("data-on")==="1"){el.textContent="••••••";el.setAttribute("data-on","0");}else{el.textContent=pw;el.setAttribute("data-on","1");}}
async function _newAccount(){
  var name=await igAskText(T("Full name","Magaca buuxa"));if(!name)return;
  var user=await igAskText(T("Username","Magaca isticmaale"));if(!user)return;
  if(ACCOUNTS.find(function(a){return a.username.toLowerCase()===user.toLowerCase();})){toast(T("Username taken","Magaca la qaatay"));return;}
  var pass=await igAskText(T("Password","Sirta"));if(!pass)return;
  var role=await igAsk(T("Make admin? (OK = admin, Cancel = cashier)","Maamulaha ka dhig?"))?"admin":"cashier";
  // Scope new accounts to a specific business. Default = active business.
  // Per-business admins always get their own business. Super-admin picks.
  var scope=CURRENT_USER.bizId||CURRENT_BIZ_ID;
  if(isSuperAdmin()){
    // Number the businesses so the super-admin types "1", "2", etc. — no
    // typo risk and no accidental blank-equals-global pitfall.
    var list=BIZ_LIST.map(function(b,i){return (i+1)+") "+b.name;}).join("\n");
    var ans=await igAskText(
      T("Which business does this user belong to?\n\n","Ganacsi kee ayuu ka tirsanaa?\n\n")+
      list+"\n\n"+
      T("Type the number (or type 0 for super-admin / all-business access)","Qor lambarka (ama 0 maamulaha guud)"),
      "1"
    );
    if(ans===null)return;
    var n=parseInt(ans);
    if(isNaN(n)||n<0||n>BIZ_LIST.length){toast(T("Invalid choice","Doorasho khalad"));return;}
    if(n===0){
      if(!await igAsk(T("This user will have super-admin access to ALL businesses. Are you sure?","Maamule guud oo ka shaqeeya DHAMMAAN ganacsiyada. Ma hubtaa?")))return;
      scope="";
    } else {
      scope=BIZ_LIST[n-1].id;
    }
  }
  ACCOUNTS.push({id:"a"+Date.now(),name:name,username:user,password:pass,role:role,bizId:scope,active:true});
  _save("pos_acc",ACCOUNTS);renderPage("users");
  var scopeLbl=scope?(BIZ_LIST.find(function(b){return b.id===scope;})||{}).name:T("super-admin (all businesses)","maamule guud");
  toast(T("User created → ","Akoon la sameeyay → ")+scopeLbl);
}
// Reassign an account to a different business — fixes accounts that were
// accidentally created as super-admin (no bizId) but should be scoped.
async function reassignAccount(id){
  if(!isSuperAdmin()){toast(T("Super-admin only","Maamulaha guud kaliya"));return;}
  var a=ACCOUNTS.find(function(x){return x.id===id;});if(!a)return;
  var list=BIZ_LIST.map(function(b,i){return (i+1)+") "+b.name;}).join("\n");
  var ans=await igAskText(
    T("Move ","U wareeji ")+a.name+T(" to which business?\n\n"," ganacsi kee?\n\n")+
    list+"\n\n"+T("Type the number (or 0 for super-admin)","Qor lambarka (ama 0 maamulaha guud)"),
    "1"
  );
  if(ans===null)return;
  var n=parseInt(ans);
  if(isNaN(n)||n<0||n>BIZ_LIST.length){toast(T("Invalid choice","Doorasho khalad"));return;}
  a.bizId=(n===0)?"":BIZ_LIST[n-1].id;
  _save("pos_acc",ACCOUNTS);renderPage("users");
  var scopeLbl=a.bizId?(BIZ_LIST.find(function(b){return b.id===a.bizId;})||{}).name:T("super-admin","maamule guud");
  toast(T("Moved → ","La wareejiyay → ")+scopeLbl);
}
async function _delAcc(id){
  var a=ACCOUNTS.find(function(x){return x.id===id;});if(!a)return;
  // Per-business admin can only delete users in their own business
  if(!isSuperAdmin()&&a.bizId!==CURRENT_USER.bizId){toast(T("Not allowed","Lama ogoolayn"));return;}
  if(!await igAsk(T("Delete user?","Tirtir?")))return;
  ACCOUNTS=ACCOUNTS.filter(function(x){return x.id!==id;});
  _save("pos_acc",ACCOUNTS);
  renderPage("users");
}

// ============================================================
//  PAGE: SETTINGS (admin only)
// ============================================================
PAGES.settings=function(){
  if(CURRENT_USER.role!=="admin")return "<div class=\"empty\">"+T("Admin only","Maamulaha kaliya")+"</div>";
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Settings","Habayn")+"</div><div class=\"phS\">"+T("Business and currency","Ganacsiga iyo lacagta")+"</div></div></div>";
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">"+T("Business info","Macluumaadka ganacsiga")+"</div></div><div class=\"bB\">";
  h+="<div class=\"fi\"><label>"+T("Business name","Magaca ganacsiga")+"</label><input id=\"st_nm\" value=\""+esc(BIZ.name||"")+"\"></div>";
  // Business type picker — drives the POS terminal layout
  h+="<div class=\"fi\"><label>"+T("Business type","Nooca ganacsiga")+"</label><select id=\"st_type\">";
  BIZ_TYPES.forEach(function(bt){
    h+="<option value=\""+bt.k+"\""+(BIZ.type===bt.k?" selected":"")+">"+bt.ic+" "+T(bt.en,bt.so)+"</option>";
  });
  h+="</select></div>";
  h+="<div class=\"fi\"><label>"+T("Address","Cinwaan")+"</label><input id=\"st_addr\" value=\""+esc(BIZ.addr||"")+"\"></div>";
  h+="<div class=\"fi\"><label>"+T("Phone","Taleefoon")+"</label><input id=\"st_ph\" value=\""+esc(BIZ.phone||"")+"\"></div>";
  h+="<div style=\"display:grid;grid-template-columns:1fr 1fr;gap:9px\">";
  h+="<div class=\"fi\"><label>"+T("Tax %","Canshuur %")+"</label><input type=\"number\" id=\"st_tax\" value=\""+(BIZ.tax||0)+"\" min=\"0\" max=\"100\" step=\"0.01\"></div>";
  h+="<div class=\"fi\"><label>"+T("Currency","Lacagta")+"</label><select id=\"st_ccy\">"+
    ["USD","SOS","SLSH"].map(function(c){return "<option"+(CURRENCY===c?" selected":"")+">"+c+"</option>";}).join("")+
    "</select></div>";
  h+="</div>";
  h+="<div style=\"display:grid;grid-template-columns:1fr 1fr;gap:9px\">";
  h+="<div class=\"fi\"><label>USD → SOS</label><input type=\"number\" id=\"st_fx_sos\" value=\""+FX_USD_TO_SOS+"\" min=\"1\"></div>";
  h+="<div class=\"fi\"><label>USD → SLSH</label><input type=\"number\" id=\"st_fx_slsh\" value=\""+FX_USD_TO_SLSH+"\" min=\"1\"></div>";
  h+="</div>";
  h+="<button class=\"btn btnP\" onclick=\"saveSettings()\">"+T("Save settings","Keydi")+"</button>";
  h+="</div></div>";

  // Sample products loader — gives a Restaurant/Cafe/Bar/Retail menu in one click
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#128218; "+T("Load sample products","Soo dejiso alaab tijaabo ah")+"</div></div><div class=\"bB\">";
  h+="<div style=\"font-size:11px;color:#666;margin-bottom:9px\">"+T("Quickly populate the catalog with a starter menu for your business type. Adds; doesn't delete.","Si dhaqsa ah u buuxi alaabta nooca ganacsigaaga. Wuxuu ku darayaa; ma tirtirayo.")+"</div>";
  h+="<div style=\"display:flex;gap:7px;flex-wrap:wrap\">";
  h+="<button class=\"btn\" onclick=\"_loadSamples('restaurant')\">&#127869; "+T("Restaurant menu","Liiska maqaayadda")+"</button>";
  h+="<button class=\"btn\" onclick=\"_loadSamples('cafe')\">&#9749; "+T("Cafe menu","Liiska kafeega")+"</button>";
  h+="<button class=\"btn\" onclick=\"_loadSamples('bar')\">&#127861; "+T("Juice / Tea bar menu","Liiska baarka casiirka")+"</button>";
  h+="<button class=\"btn\" onclick=\"_loadSamples('retail')\">&#128722; "+T("Retail items","Alaabta tafaariiq")+"</button>";
  h+="</div></div></div>";

  // Danger zone
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\" style=\"color:#bf2600\">&#9888; "+T("Danger zone","Halista")+"</div></div><div class=\"bB\">";
  h+="<button class=\"btn btnR\" onclick=\"_wipeSales()\">"+T("Clear all sales history","Tirtir taariikhda iibka")+"</button> ";
  h+="<button class=\"btn btnR\" onclick=\"_wipeProducts()\">"+T("Delete all products","Tirtir dhammaan alaabta")+"</button>";
  h+="</div></div>";
  return h;
};
async function _wipeProducts(){if(!await igAsk(T("Delete EVERY product in "+BIZ.name+"? Cannot be undone.","Tirtir DHAMMAAN alaabta "+BIZ.name+"?")))return;PRODUCTS=PRODUCTS.filter(function(p){return p.bizId!==CURRENT_BIZ_ID;});_save("pos_prod",PRODUCTS);toast(T("Products cleared","La nadiifyay"));renderPage("settings");}
async function _loadSamples(kind){
  var menus={
    restaurant:[
      {name:"Beef Burger",cat:"Mains",price:8.50,stock:99,icon:"🍔"},
      {name:"Chicken Wrap",cat:"Mains",price:6.75,stock:99,icon:"🌯"},
      {name:"Margherita Pizza",cat:"Mains",price:12.00,stock:99,icon:"🍕"},
      {name:"Caesar Salad",cat:"Salads",price:7.50,stock:99,icon:"🥗"},
      {name:"French Fries",cat:"Sides",price:3.00,stock:99,icon:"🍟"},
      {name:"Onion Rings",cat:"Sides",price:3.50,stock:99,icon:"🧅"},
      {name:"Grilled Salmon",cat:"Mains",price:14.00,stock:99,icon:"🐟"},
      {name:"Mango Juice",cat:"Drinks",price:3.00,stock:99,icon:"🥭"},
      {name:"Lemonade",cat:"Drinks",price:2.50,stock:99,icon:"🍋"},
      {name:"Ice Cream",cat:"Desserts",price:4.00,stock:99,icon:"🍦"}
    ],
    cafe:[
      {name:"Espresso",cat:"Coffee",price:2.50,stock:99,icon:"☕"},
      {name:"Cappuccino",cat:"Coffee",price:3.50,stock:99,icon:"☕"},
      {name:"Latte",cat:"Coffee",price:3.75,stock:99,icon:"☕"},
      {name:"Iced Coffee",cat:"Coffee",price:3.25,stock:99,icon:"🧊"},
      {name:"Green Tea",cat:"Tea",price:2.50,stock:99,icon:"🍵"},
      {name:"Chai Latte",cat:"Tea",price:3.50,stock:99,icon:"🫖"},
      {name:"Croissant",cat:"Pastries",price:2.75,stock:99,icon:"🥐"},
      {name:"Blueberry Muffin",cat:"Pastries",price:3.00,stock:99,icon:"🧁"},
      {name:"Cheesecake Slice",cat:"Desserts",price:4.50,stock:99,icon:"🍰"},
      {name:"Bagel & Cream Cheese",cat:"Breakfast",price:4.00,stock:99,icon:"🥯"}
    ],
    bar:[
      {name:"Black Tea",cat:"Tea",price:2.00,stock:99,icon:"🍵"},
      {name:"Green Tea",cat:"Tea",price:2.25,stock:99,icon:"🍵"},
      {name:"Mint Tea",cat:"Tea",price:2.50,stock:99,icon:"🌿"},
      {name:"Spiced Tea",cat:"Tea",price:2.75,stock:99,icon:"🫖"},
      {name:"Fresh Orange Juice",cat:"Juices",price:3.50,stock:99,icon:"🍊"},
      {name:"Mango Juice",cat:"Juices",price:3.50,stock:99,icon:"🥭"},
      {name:"Watermelon Juice",cat:"Juices",price:3.25,stock:99,icon:"🍉"},
      {name:"Banana Smoothie",cat:"Smoothies",price:4.00,stock:99,icon:"🍌"},
      {name:"Strawberry Smoothie",cat:"Smoothies",price:4.25,stock:99,icon:"🍓"},
      {name:"Sparkling Water",cat:"Soft",price:2.00,stock:99,icon:"💧"},
      {name:"Buffalo Wings",cat:"Snacks",price:7.00,stock:99,icon:"🍗"},
      {name:"Nachos",cat:"Snacks",price:6.00,stock:99,icon:"🌮"}
    ],
    retail:[
      {name:"T-Shirt Plain",cat:"Apparel",price:9.99,stock:50,icon:"👕",sku:"TS-001",barcode:"1000001"},
      {name:"Denim Jeans",cat:"Apparel",price:29.99,stock:30,icon:"👖",sku:"JN-001",barcode:"1000002"},
      {name:"Sneakers",cat:"Footwear",price:49.99,stock:25,icon:"👟",sku:"SN-001",barcode:"1000003"},
      {name:"Sunglasses",cat:"Accessories",price:14.99,stock:60,icon:"🕶️",sku:"SG-001",barcode:"1000004"},
      {name:"Backpack",cat:"Accessories",price:34.99,stock:20,icon:"🎒",sku:"BP-001",barcode:"1000005"},
      {name:"Notebook A5",cat:"Stationery",price:3.50,stock:120,icon:"📓",sku:"NB-001",barcode:"1000006"},
      {name:"Ballpoint Pen",cat:"Stationery",price:1.50,stock:200,icon:"🖊️",sku:"PN-001",barcode:"1000007"},
      {name:"USB Flash Drive 32GB",cat:"Electronics",price:8.99,stock:40,icon:"💾",sku:"US-001",barcode:"1000008"},
      {name:"Wireless Earbuds",cat:"Electronics",price:24.99,stock:18,icon:"🎧",sku:"EB-001",barcode:"1000009"},
      {name:"Phone Charger",cat:"Electronics",price:11.99,stock:55,icon:"🔌",sku:"CH-001",barcode:"1000010"}
    ]
  };
  var items=menus[kind];if(!items)return;
  if(!await igAsk(T("Add "+items.length+" sample items to "+BIZ.name+"?","Ku dar "+items.length+" alaab tijaabo ah "+BIZ.name+"?")))return;
  var added=0;
  items.forEach(function(it){
    if(forBiz(PRODUCTS).find(function(p){return p.name.toLowerCase()===it.name.toLowerCase();}))return;
    PRODUCTS.push(Object.assign({id:"p"+Date.now()+"-"+(added++),bizId:CURRENT_BIZ_ID},it));
  });
  _save("pos_prod",PRODUCTS);
  toast(T(added+" items added","Ku dartay "+added));
  renderPage("settings");
}
function saveSettings(){
  BIZ.name=$("st_nm").value.trim()||"Casri POS";
  BIZ.type=$("st_type").value||"shop";
  BIZ.addr=$("st_addr").value.trim();
  BIZ.phone=$("st_ph").value.trim();
  BIZ.tax=parseFloat($("st_tax").value)||0;
  BIZ.currency=$("st_ccy").value;
  CURRENCY=BIZ.currency;
  var fxs=parseInt($("st_fx_sos").value);if(!isNaN(fxs)&&fxs>0)FX_USD_TO_SOS=fxs;
  var fxsh=parseInt($("st_fx_slsh").value);if(!isNaN(fxsh)&&fxsh>0)FX_USD_TO_SLSH=fxsh;
  _save("pos_biz",BIZ);
  _save("pos_fx",{sos:FX_USD_TO_SOS,slsh:FX_USD_TO_SLSH});
  renderUser();
  toast(T("Saved","La keydiyay"));
}
async function _wipeSales(){if(!await igAsk(T("Delete ALL sales in "+BIZ.name+"? Cannot be undone.","Tirtir DHAMMAAN iibka "+BIZ.name+"?")))return;SALES=SALES.filter(function(s){return s.bizId!==CURRENT_BIZ_ID;});_save("pos_sales",SALES);toast(T("Cleared","La nadiifyay"));renderPage("settings");}

// ── BOOT ─────────────────────────────────────────────────────
(function(){
  var fx=_load("pos_fx",null);
  if(fx&&fx.sos)FX_USD_TO_SOS=fx.sos;
  if(fx&&fx.slsh)FX_USD_TO_SLSH=fx.slsh;
  // Register service worker
  if("serviceWorker" in navigator){
    window.addEventListener("load",function(){navigator.serviceWorker.register("sw.js").catch(function(){});});
  }
  // Pre-select EN
  setTimeout(function(){
    $("langEN").classList.add("on");
    $("loginUser").focus();
  },50);
  // Enter to submit on login
  $("loginPass").addEventListener("keydown",function(e){if(e.key==="Enter")doLogin();});
  $("loginUser").addEventListener("keydown",function(e){if(e.key==="Enter")$("loginPass").focus();});
})();
