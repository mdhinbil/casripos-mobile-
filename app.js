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
function _save(key,val){
  try{
    localStorage.setItem(key,JSON.stringify(val));
    // Stamp when WE last changed this key. cloudPull compares against the
    // remote stamp so a device never overwrites newer data with older.
    localStorage.setItem("pos_ts_"+key,String(Date.now()));
  }catch(e){toast("Storage full");}
  // Queue a cloud push. No-op until the user signs in to sync.
  try{if(typeof cloudQueue==="function")cloudQueue(key);}catch(e){}
}

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
  if(!isSuperAdmin()){toast(T("Not allowed","Lama ogoolaan"));return;}
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
// Show the POS scan bar for shops/retail, and for ANY business that has started
// putting barcodes on its products. (It used to be retail-only, so a shop or
// grocery could never scan.) The SKU/barcode fields themselves are now always
// available on the product form regardless of business type.
function _bizUsesBarcode(){
  if(BIZ.type==="retail"||BIZ.type==="shop")return true;
  return forBiz(PRODUCTS).some(function(p){return !!(p.barcode||p.sku);});
}
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
  // Multi-line messages: first line is the heading, the rest goes in the body
  // (which preserves newlines). Putting it all in the heading collapsed the
  // line breaks and produced one unreadable run-on line.
  var all=String(text||T("Enter value","Geli qiimaha")).split("\n");
  var t=$("pr_title");if(t)t.textContent=all[0];
  var x=$("pr_text");if(x)x.textContent=all.slice(1).join("\n").trim();
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

// Pick one option from a list. opts = [{v:value, t:label}, …]
// Returns the chosen value, or null if cancelled.
var _IG_COK=null,_IG_CNO=null;
function igChoice(title,text,opts,defVal,onOk,onCancel){
  _IG_COK=onOk||null;_IG_CNO=onCancel||null;
  var t=$("ch_title");if(t)t.textContent=title||T("Choose","Dooro");
  var x=$("ch_text");if(x)x.textContent=text||"";
  var sel=$("ch_sel");
  if(sel){
    sel.innerHTML=(opts||[]).map(function(o){
      return "<option value=\""+esc(String(o.v))+"\""+(String(o.v)===String(defVal)?" selected":"")+">"+esc(o.t)+"</option>";
    }).join("");
  }
  var no=$("ch_no");if(no)no.textContent=T("Cancel","Jooji");
  var ok=$("ch_ok");if(ok)ok.textContent=T("OK","Haa");
  if(!$("M_choice")){if(onCancel)onCancel();return;}
  openM("M_choice");
}
function igChoiceOk(){var s=$("ch_sel");var v=s?s.value:null;var cb=_IG_COK;_IG_COK=_IG_CNO=null;closeM("M_choice");if(typeof cb==="function")cb(v);}
function igChoiceCancel(){var cb=_IG_CNO;_IG_COK=_IG_CNO=null;closeM("M_choice");if(typeof cb==="function")cb(null);}
function igAskChoice(title,text,opts,defVal){
  return new Promise(function(res){
    igChoice(title,text,opts,defVal,function(v){res(v);},function(){res(null);});
  });
}

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
  {id:"invoices",  en:"Invoices",      so:"Qaansheegyada",   ic:"🧾"},
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
  if(!topProds.length){h+="<div class=\"empty\"><div class=\"emIc\">&#128181;</div>"+T("No sales yet today","Waxba lama iibin maanta")+"</div>";}
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
  h+="<div class=\"ttl\">&#128722; "+T("Cart","Selleda")+" <span id=\"cartCt\">("+CART.length+")</span></div>";
  h+="<button class=\"clr\" onclick=\"event.stopPropagation();_clearCart()\">&#10005; "+T("Clear","Cadee")+"</button>";
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
  if(!p){toast(T("No product with code ","Alaab lambarkan ma leh ")+code);input.select();return;}
  if(p.stock<=0){toast(T("Out of stock: ","Kaydka ma jiro: ")+p.name);input.value="";input.focus();return;}
  addToCart(p.id);
  toast(p.name+" +1");            // confirm the scan actually landed
  input.value="";input.focus();   // ready for the next scan
}
function _uniqueCats(){var s={};forBiz(PRODUCTS).forEach(function(p){if(p.cat)s[p.cat]=1;});return Object.keys(s).sort();}
function _filterProducts(){
  $("prodGrid").innerHTML=_renderProductCards();
}
function _renderProductCards(){
  var q=($("posQ")&&$("posQ").value||"").toLowerCase();
  var list=forBiz(PRODUCTS).filter(function(p){
    if(CAT_FILTER!=="all"&&p.cat!==CAT_FILTER)return false;
    // Search matches name, category, barcode and SKU — so typing or scanning a
    // code into the normal search box finds the product too.
    if(q&&p.name.toLowerCase().indexOf(q)<0
        &&(p.cat||"").toLowerCase().indexOf(q)<0
        &&(p.barcode||"").toLowerCase().indexOf(q)<0
        &&(p.sku||"").toLowerCase().indexOf(q)<0)return false;
    return true;
  });
  if(!list.length)return "<div class=\"empty\" style=\"grid-column:1/-1\"><div class=\"emIc\">&#128269;</div>"+T("No products match","Wax u dhigma ma jiraan")+"</div>";
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
    else{toast(T("Not enough stock","Kaydku kuma filna"));return;}
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
async function _clearCart(){if(CART.length&&!await igAsk(T("Clear the cart?","Selleda cadee?")))return;CART=[];_refreshCart();}
function _toggleCart(){var c=$("posCart");if(c)c.classList.toggle("open");}
function _refreshCart(){
  var cl=$("cartList");if(cl)cl.innerHTML=_renderCart();
  var ct=$("cartCt");if(ct)ct.textContent="("+CART.length+")";
  var sum=document.querySelector(".posSum");
  if(sum)sum.outerHTML=_renderCartSummary();
}
function _renderCart(){
  if(!CART.length)return "<div class=\"empty\"><div class=\"emIc\">&#128722;</div>"+T("Cart is empty","Selledu waa madhantahay")+"</div>";
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
  h+="<div class=\"sumRow\"><span>"+T("Items","Alaabta")+"</span><span>"+t.items+"</span></div>";
  h+="<div class=\"sumRow\"><span>"+T("Subtotal","Wadarta")+"</span><span>"+money(t.sub)+"</span></div>";
  if(BIZ.tax>0)h+="<div class=\"sumRow\"><span>"+T("Tax","Canshuur")+" ("+BIZ.tax+"%)</span><span>"+money(t.tax)+"</span></div>";
  h+="<div class=\"sumRow tot\"><span>"+T("Total","Wadarta guud")+"</span><span>"+money(t.tot)+"</span></div>";
  h+="</div>";
  return h;
}
// ── PAYMENT ──────────────────────────────────────────────────
// Checkout now asks HOW the customer is paying before recording the sale:
// cash (with change owed), card, or mobile money (ZAAD / EVC Plus / eDahab).
var PAY_METHOD="cash";
function payLabel(m){
  return m==="card"?T("Card","Risiidh")
       : m==="mobile"?T("Mobile money","Lacag mobile")
       : T("Cash","Cadaan");
}
function setPayMethod(m){
  PAY_METHOD=m;
  var box=$("pay_methods");
  if(box){
    var bs=box.querySelectorAll(".payM");
    for(var i=0;i<bs.length;i++)bs[i].classList.toggle("on",bs[i].getAttribute("data-m")===m);
  }
  var cash=$("pay_cash_box"),ref=$("pay_ref_box"),pw=$("pay_prov_wrap");
  if(cash)cash.style.display=(m==="cash")?"block":"none";
  if(ref)ref.style.display=(m==="cash")?"none":"block";
  if(pw)pw.style.display=(m==="mobile")?"block":"none";   // provider list is mobile-money only
  _payChange();
}
// Live change calculation. Amounts are typed in the DISPLAY currency, so convert
// back to the USD base the cart totals use before comparing.
function _payFx(){
  if(CURRENCY==="SOS")return FX_USD_TO_SOS;
  if(CURRENCY==="SLSH")return FX_USD_TO_SLSH;
  return 1;
}
function _payChange(){
  var el=$("pay_change"),row=$("pay_change_row");
  if(!el)return;
  var due=_cartTotals().tot;
  var raw=parseFloat(($("pay_recv")||{}).value);
  if(isNaN(raw)||raw<=0){el.textContent="—";if(row)row.classList.remove("short");return;}
  var recvUSD=raw/_payFx();
  var diff=recvUSD-due;
  if(diff>=0){el.textContent=money(diff);if(row)row.classList.remove("short");}
  else{el.textContent="-"+money(Math.abs(diff));if(row)row.classList.add("short");}
}
function openPayModal(){
  var t=_cartTotals();
  var lbl=$("pay_lbl");if(lbl)lbl.textContent=T("Amount due","Lacagta la bixinayo");
  var amt=$("pay_amt");if(amt)amt.textContent=money(t.tot);
  var ttl=$("pay_t");if(ttl)ttl.textContent=T("Payment","Lacag bixinta");
  // bilingual labels
  var m={payM_cash:[T("Cash","Cadaan"),0],payM_card:[T("Card","Risiidh"),0],payM_mobile:[T("Mobile","Mobile"),0]};
  Object.keys(m).forEach(function(k){var e=$(k);if(e)e.textContent=m[k][0];});
  var rl=$("pay_recv_l");if(rl)rl.textContent=T("Amount received","Lacagta la helay");
  var cl=$("pay_change_l");if(cl)cl.textContent=T("Change","Baaqiga");
  var pl=$("pay_prov_l");if(pl)pl.textContent=T("Provider","Adeeg bixiyaha");
  var fl=$("pay_ref_l");if(fl)fl.textContent=T("Reference (optional)","Tixraac (ikhtiyaari)");
  var cx=$("pay_cancel");if(cx)cx.textContent=T("Cancel","Jooji");
  var dn=$("pay_done");if(dn)dn.textContent=T("Complete sale","Dhammee iibka");
  var rv=$("pay_recv");if(rv)rv.value="";
  var rf=$("pay_ref");if(rf)rf.value="";
  // Quick cash buttons: exact amount, then sensible round-ups in the display currency
  var q=$("pay_quick");
  if(q){
    var due=t.tot*_payFx();
    var opts=[due];
    [1,5,10,20,50,100].forEach(function(step){
      var v=Math.ceil(due/step)*step;
      if(v>due&&opts.indexOf(v)<0&&opts.length<5)opts.push(v);
    });
    q.innerHTML=opts.map(function(v,i){
      var lab=i===0?T("Exact","Saxda"):(CURRENCY==="USD"?"$":"")+Math.round(v).toLocaleString();
      return "<button type=\"button\" onclick=\"_paySetRecv("+v+")\">"+lab+"</button>";
    }).join("");
  }
  setPayMethod("cash");
  openM("M_pay");
}
function _paySetRecv(v){
  var rv=$("pay_recv");
  if(rv){rv.value=(Math.round(v*100)/100);_payChange();}
}
function confirmPayment(){
  var t=_cartTotals();
  var paid=null,change=0,ref="",prov="";
  if(PAY_METHOD==="cash"){
    var raw=parseFloat(($("pay_recv")||{}).value);
    if(!isNaN(raw)&&raw>0){
      paid=raw/_payFx();
      if(paid+1e-9<t.tot){toast(T("Amount received is less than the total","Lacagta la helay way ka yar tahay wadarta"));return;}
      change=paid-t.tot;
    } else {
      paid=t.tot;   // no amount typed → assume exact
    }
  } else {
    ref=(($("pay_ref")||{}).value||"").trim();
    if(PAY_METHOD==="mobile")prov=(($("pay_prov")||{}).value||"").trim();
    paid=t.tot;
  }
  closeM("M_pay");
  _completeSale({method:PAY_METHOD,paid:paid,change:change,ref:ref,provider:prov});
}
function checkout(){
  if(!CART.length){toast(T("Add items first","Marka hore alaab ku dar"));return;}
  openPayModal();
}
function _completeSale(pay){
  if(!CART.length)return;
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
    orderType:_bizUsesTables()?ORDER_TYPE:"",
    // How it was paid — cash / card / mobile (+ change owed, provider, reference)
    payMethod:(pay&&pay.method)||"cash",
    paid:(pay&&pay.paid)||t.tot,
    change:(pay&&pay.change)||0,
    payProvider:(pay&&pay.provider)||"",
    payRef:(pay&&pay.ref)||""
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

// Build the receipt as a fixed-width monospace slip (32 cols = standard 58mm
// thermal paper, and narrow enough to fit a phone without sideways scrolling).
// Long product names wrap onto their own lines instead of being truncated, and
// each item shows "qty x unit price" so the maths is checkable.
function _receiptText(sale){
  var w=32;
  function pad(n){return n>0?new Array(n+1).join(" "):"";}
  function center(s){s=String(s||"");if(s.length>=w)return s.slice(0,w);return pad(Math.floor((w-s.length)/2))+s;}
  function line(a,b){a=String(a||"");b=String(b||"");return a+pad(Math.max(1,w-a.length-b.length))+b;}
  function wrap(s,max){
    s=String(s||"").trim();var out=[];
    while(s.length>max){
      var cut=s.lastIndexOf(" ",max);
      if(cut<=0)cut=max;
      out.push(s.slice(0,cut));
      s=s.slice(cut).replace(/^\s+/,"");
    }
    if(s)out.push(s);
    return out.length?out:[""];
  }
  var d=new Date(sale.date);
  var when=d.toLocaleDateString()+" "+d.toLocaleTimeString([],{hour:"2-digit",minute:"2-digit"});

  var h="";
  h+=center((BIZ.name||"Casri POS").toUpperCase())+"\n";
  if(BIZ.addr)wrap(BIZ.addr,w).forEach(function(l){h+=center(l)+"\n";});
  if(BIZ.phone)h+=center(BIZ.phone)+"\n";
  h+="\n"+"=".repeat(w)+"\n";
  h+=line(T("Receipt","Risiidh"),"#"+String(sale.id).slice(-6))+"\n";
  h+=line(T("Date","Taariikh"),when)+"\n";
  h+=line(T("Cashier","Iibiyaha"),sale.cashier||"-")+"\n";
  if(sale.tableNo)h+=line(T("Table","Miiska"),"#"+sale.tableNo)+"\n";
  if(sale.orderType)h+=line(T("Order","Dalabka"),sale.orderType)+"\n";
  h+="=".repeat(w)+"\n";
  (sale.items||[]).forEach(function(it){
    wrap(it.name,w).forEach(function(l){h+=l+"\n";});
    h+=line("  "+it.qty+" x "+money(it.price),money(it.price*it.qty))+"\n";
  });
  h+="-".repeat(w)+"\n";
  h+=line(T("Subtotal","Wadarta"),money(sale.subtotal))+"\n";
  if(sale.tax>0)h+=line(T("Tax","Canshuurta"),money(sale.tax))+"\n";
  h+="=".repeat(w)+"\n";
  h+=line(T("TOTAL","WADARTA"),money(sale.total))+"\n";
  h+="=".repeat(w)+"\n";
  // How it was paid — plus change owed for cash, or the provider/ref for mobile & card
  var pm=sale.payMethod||"cash";
  h+=line(T("Paid by","Lacag bixin"),payLabel(pm)+(pm==="mobile"&&sale.payProvider?" ("+sale.payProvider+")":""))+"\n";
  if(pm==="cash"&&sale.paid>sale.total){
    h+=line(T("Received","La helay"),money(sale.paid))+"\n";
    h+=line(T("Change","Baaqiga"),money(sale.change||0))+"\n";
  }
  if(sale.payRef)h+=line(T("Ref","Tixraac"),String(sale.payRef).slice(0,20))+"\n";
  h+="\n"+center(T("Thank you!","Mahadsanid!"))+"\n";
  return h;
}
function _showReceipt(sale){
  $("rec_body").textContent=_receiptText(sale);
  openM("M_rec");
}

// ── Cloud sync UI (logic lives in cloud.js) ─────────────────
function _cloudSettingsHTML(){
  if(typeof CLOUD==="undefined")return "<div style=\"font-size:11px;color:#666\">"+T("Cloud sync unavailable","Cloud lama heli karo")+"</div>";
  var h="";
  if(!CLOUD.on){
    h+="<div style=\"font-size:11px;color:#666;margin-bottom:10px\">"+
       T("Sign in to keep this device in step with your other devices, and to keep a copy of your data off the phone. The till keeps working without it.",
         "Gal si aad qalabkan ula socodsiiso qalabkaaga kale, oo aad nuqul xogtaada uga hayso taleefanka dibaddiisa. Iibku wuu shaqeeyaa la'aanteed.")+"</div>";
    h+="<div style=\"display:grid;grid-template-columns:1fr 1fr;gap:9px;max-width:420px\">";
    h+="<div class=\"fi\"><label>"+T("Email","Email")+"</label><input type=\"email\" id=\"cl_em\" autocomplete=\"username\" placeholder=\"shop@example.com\"></div>";
    h+="<div class=\"fi\"><label>"+T("Password","Sirta")+"</label><input type=\"password\" id=\"cl_pw\" autocomplete=\"current-password\" placeholder=\"••••••\"></div>";
    h+="</div>";
    h+="<div style=\"display:flex;gap:7px;flex-wrap:wrap;margin-top:4px\">";
    h+="<button class=\"btn btnP\" onclick=\"doCloudSignIn(false)\">"+T("Sign in","Gal")+"</button>";
    h+="<button class=\"btn\" onclick=\"doCloudSignIn(true)\">"+T("Create account","Samee akoon")+"</button>";
    h+="</div>";
  } else {
    h+="<div style=\"font-size:12px;margin-bottom:4px\">"+T("Signed in as","Waxaad tahay")+" <strong>"+esc(CLOUD.email)+"</strong></div>";
    h+="<div style=\"font-size:11px;color:#666;margin-bottom:10px\" id=\"cl_last\">"+_cloudLastText()+"</div>";
    h+="<div style=\"display:flex;gap:7px;flex-wrap:wrap\">";
    h+="<button class=\"btn btnP\" onclick=\"doCloudSync()\">&#8635; "+T("Sync now","Hadda isku xidh")+"</button>";
    h+="<button class=\"btn\" onclick=\"doCloudUpload()\">&#11014; "+T("Upload this device","Soo dir qalabkan")+"</button>";
    h+="<button class=\"btn btnR\" onclick=\"doCloudSignOut()\">"+T("Sign out of sync","Ka bax cloud")+"</button>";
    h+="</div>";
  }
  return h;
}
function _cloudLastText(){
  if(typeof CLOUD==="undefined")return "";
  if(CLOUD.lastError)return "&#9888; "+esc(CLOUD.lastError);
  if(!CLOUD.lastSync)return T("Not synced yet","Weli lama isku xidhin");
  return T("Last synced","Markii ugu dambeysay")+": "+new Date(CLOUD.lastSync).toLocaleString();
}
// Small coloured dot in the Cloud sync header.
function _cloudPaint(state){
  var d=$("cloudDot");
  if(d){
    var map={ok:["#1f7a55",T("Synced","La isku xidhay")],sync:["#b7791f",T("Syncing…","Waa isku xidhayaa…")],
              err:["#c62f16",T("Sync problem","Dhibaato")],off:["#98a2b3",T("Off","Damin")]};
    var m=map[state]||map.off;
    d.innerHTML="<span style=\"display:inline-flex;align-items:center;gap:6px;font-size:10.5px;font-weight:700;color:"+m[0]+"\">"+
                "<span style=\"width:8px;height:8px;border-radius:50%;background:"+m[0]+";display:inline-block\"></span>"+m[1]+"</span>";
  }
  var l=$("cl_last");if(l)l.innerHTML=_cloudLastText();
}
function _cloudRefresh(){
  var b=$("cloudBox");if(b)b.innerHTML=_cloudSettingsHTML();
  _cloudPaint(CLOUD.lastError?"err":(CLOUD.on?"ok":"off"));
}
function doCloudSignIn(isNew){
  var em=($("cl_em")&&$("cl_em").value||"").trim();
  var pw=($("cl_pw")&&$("cl_pw").value||"");
  if(!em||!pw){toast(T("Enter email and password","Geli email iyo sirta"));return;}
  _cloudPaint("sync");
  cloudSignIn(em,pw,isNew).then(async function(remote){
    toast(isNew?T("Sync account created","Akoon cloud la sameeyay"):T("Signed in to sync","Cloud waad gashay"));
    var local=cloudLocalInfo();
    // Nothing in the cloud yet → this device seeds it. Safe: nothing to lose.
    if(!remote.has){
      await cloudPushAll();_cloudRefresh();
      toast(T("This device is now your cloud copy","Qalabkan hadda waa nuqulkaaga cloud-ka"));
      return;
    }
    // Cloud HAS data. Never guess the direction from timestamps — a fresh phone
    // has newer stamps than a PC that uploaded yesterday, and guessing would
    // push the empty phone over the real data. Ask, and show both sides.
    function sum(o){return o.businesses+" "+T("businesses","ganacsi")+", "+o.products+" "+T("products","alaab")+", "+o.sales+" "+T("sales","iib");}
    var pick=await igAskChoice(
      T("Which copy is correct?","Nuqulkee saxa ah?"),
      T("In the cloud","Cloud-ka ku jira")+":  "+sum(remote)+"\n"+
      T("On this device","Qalabkan ku jira")+":  "+sum(local)+"\n\n"+
      T("The other copy will be replaced.","Nuqulka kale waa la beddeli doonaa."),
      [{v:"down",t:"⬇ "+T("Use the cloud copy (download)","Isticmaal kan cloud-ka (soo deji)")},
       {v:"up",  t:"⬆ "+T("Use this device (upload)","Isticmaal qalabkan (soo dir)")}],
      "down");
    if(pick===null){_cloudRefresh();return;}
    if(pick==="up"){
      await cloudPushAll();_cloudRefresh();
      toast(T("Uploaded to cloud","Cloud-ka waa loo diray"));
    } else {
      await cloudPull(true);            // force: ignore timestamps, take the cloud
      igAlert(T("Cloud data downloaded. The app will reload.",
                "Xogta cloud-ka waa la soo dejiyay. Barnaamijku wuu dib u furmi doonaa."),
              function(){location.reload();});
    }
  }).catch(function(e){
    CLOUD.lastError=_cloudErrText(e.message);
    _cloudRefresh();
    toast(CLOUD.lastError);
  });
}
function doCloudSync(){
  cloudPull(false).then(function(n){
    if(n>0){
      igAlert(T("New data downloaded. The app will reload.","Xog cusub ayaa la soo dejiyay. Barnaamijku wuu dib u furmi doonaa."),
              function(){location.reload();});
    } else {
      cloudFlush().then(function(){_cloudRefresh();toast(T("Up to date","Waa la wada socdaa"));});
    }
  });
}
function doCloudUpload(){
  igConfirm(T("Send everything on THIS device to the cloud, replacing what is there?",
              "U dir wax kasta oo QALABKAN ku jira cloud-ka, beddelna waxa jira?"),function(){
    cloudPushAll().then(function(){_cloudRefresh();toast(T("Uploaded","La soo diray"));});
  },T("Upload","Soo dir"));
}
function doCloudSignOut(){
  igConfirm(T("Stop syncing on this device? Your data stays here.",
              "Jooji isku xidhka qalabkan? Xogtaadu halkan way sii joogtaa."),function(){
    cloudSignOut();_cloudRefresh();toast(T("Sync off","Cloud waa damin"));
  },T("Sign out","Ka bax"));
}

// ============================================================
//  ACCOUNT RECOVERY — reachable from the login screen.
//  There was no way back in at all: forget the password and the till was dead,
//  with the shop's own products and sales locked inside it. Cloud sync made it
//  sharper, because signing in on a second device replaces that device's staff
//  logins with the first device's.
//
//  Two of the three routes require proof of ownership (the cloud password, or
//  a backup file), and both restore ONLY the account list — never sales — so
//  neither can be used to quietly lift a shop's takings. The third resets the
//  admin password and is deliberately last, loud, and non-destructive to data.
// ============================================================
function openRecover(){
  [["rc_t",T("Can't sign in?","Ma geli kartid?")],
   ["rc_s",T("Pick whichever you have.","Dooro midka aad haysato.")],
   ["rc_1h",T("1. Restore your staff logins from cloud sync","1. Ka soo celi cloud-ka isticmaalayaasha")],
   ["rc_1d",T("If this shop uses cloud sync, sign in with that email and password.","Haddii dukaankan cloud isticmaalo, gali email-ka iyo furaha.")],
   ["rc_1b",T("Restore logins","Soo celi isticmaalayaasha")],
   ["rc_2h",T("2. Restore from a backup file","2. Ka soo celi fayl kayd ah")],
   ["rc_2d",T("Pick a backup you exported earlier. Only the staff logins are restored.","Dooro kayd aad hore u samaysay. Kaliya isticmaalayaasha ayaa soo noqonaya.")],
   ["rc_3h",T("3. Last resort — reset the admin password","3. Ugu dambeyn — dib u deji furaha admin-ka")],
   ["rc_3d",T("Use only if you have neither of the above. Your products and sales are kept.","Isticmaal haddii aadan labadaas midna haysan. Alaabta iyo iibku way sii jiraan.")],
   ["rc_3b",T("Reset admin password","Dib u deji furaha admin")],
   ["rc_close",T("Close","Xir")]
  ].forEach(function(p){var e=$(p[0]);if(e)e.textContent=p[1];});
  var f=$("rc_file");if(f)f.value="";
  openM("M_recover");
}
// Tell the user which usernames now exist, so they know what to type.
function _recoverDone(list){
  var names=(list||[]).filter(function(a){return a&&a.active!==false;})
                      .map(function(a){return a.username;}).slice(0,8);
  closeM("M_recover");
  igAlert(T("Staff logins restored.\n\nYou can sign in with:\n","Isticmaalayaashii waa la soo celiyay.\n\nWaxaad ku geli kartaa:\n")+
          "  "+names.join("\n  ")+
          T("\n\nUse the password for that account.","\n\nIsticmaal furaha akoonkaas."),
          function(){location.reload();});
}
function recoverFromCloud(){
  var em=($("rc_em")&&$("rc_em").value||"").trim();
  var pw=($("rc_pw")&&$("rc_pw").value||"");
  if(!em||!pw){toast(T("Enter the sync email and password","Geli email-ka iyo furaha cloud-ka"));return;}
  if(typeof cloudRecoverAccounts!=="function"){toast(T("Cloud sync unavailable","Cloud lama heli karo"));return;}
  toast(T("Checking…","Waa la hubinayaa…"));
  cloudRecoverAccounts(em,pw).then(function(list){
    if(!list||!list.length){toast(T("No staff logins found in the cloud","Cloud-ka lagama helin isticmaalayaal"));return;}
    _recoverDone(list);
  }).catch(function(e){
    toast(_cloudErrText(e.message));
  });
}
function recoverFromBackup(input){
  var file=input&&input.files&&input.files[0];if(!file)return;
  var r=new FileReader();
  r.onload=function(){
    var obj;
    try{obj=JSON.parse(r.result);}catch(e){toast(T("That file isn't a valid backup","Faylkaasi ma aha kayd sax ah"));return;}
    if(!obj||obj.app!=="CasriPOS"||!obj.data||!obj.data.pos_acc){
      toast(T("No staff logins in that file","Faylkaas isticmaalayaal ma laha"));return;
    }
    try{
      localStorage.setItem("pos_acc",obj.data.pos_acc);
      _recoverDone(JSON.parse(obj.data.pos_acc));
    }catch(e){toast(T("Could not restore","Lama soo celin karin"));}
  };
  r.readAsText(file);
}
async function recoverResetAdmin(){
  if(!await igAsk(
      T("Reset the admin password on this device?\n\nProducts, sales and invoices are NOT deleted. Anyone holding this phone can do this, so change the password afterwards.",
        "Dib u deji furaha admin-ka qalabkan?\n\nAlaabta, iibka iyo qaansheegyada MA tirtiraysid. Qof kasta oo taleefankan haysta wuu samayn karaa, markaa beddel furaha ka dib."),
      T("Reset","Dib u deji")))return;
  var pass="casri"+Math.floor(1000+Math.random()*9000);
  var list=[];
  try{list=JSON.parse(localStorage.getItem("pos_acc")||"[]");}catch(e){}
  var adm=list.find(function(a){return a&&a.username&&a.username.toLowerCase()==="admin";});
  if(adm){adm.password=pass;adm.active=true;adm.role="admin";}
  else{list.unshift({id:"a"+Date.now(),name:"Admin",username:"admin",password:pass,role:"admin",bizId:"",active:true});}
  try{localStorage.setItem("pos_acc",JSON.stringify(list));}catch(e){toast(T("Could not save","Lama keydin karin"));return;}
  closeM("M_recover");
  igAlert(T("Sign in with:\n\n  Username: admin\n  Password: ","Ku gal:\n\n  Isticmaale: admin\n  Furaha: ")+pass+
          T("\n\nWrite this down, then change it in Users.","\n\nQor, kadibna ka beddel Isticmaalayaasha."),
          function(){location.reload();});
}

// ============================================================
//  BACKUP / RESTORE
//  Casri POS keeps everything in this device's localStorage — there is no
//  server. So a lost or wiped phone means every sale and product is gone, and
//  data can't move from a PC to a till. Export writes one .json holding all of
//  it; Import restores it on any device.
// ============================================================
var BACKUP_KEYS=["pos_biz_list","pos_current_biz","pos_prod","pos_sales","pos_inv","pos_acc","pos_fx","pos_biz"];
var BACKUP_VERSION=1;
function _backupObject(){
  var data={};
  BACKUP_KEYS.forEach(function(k){
    try{var v=localStorage.getItem(k);if(v!==null)data[k]=v;}catch(e){}
  });
  return {
    app:"CasriPOS",
    version:BACKUP_VERSION,
    exportedAt:new Date().toISOString(),
    businesses:(BIZ_LIST||[]).length,
    products:(PRODUCTS||[]).length,
    sales:(SALES||[]).length,
    data:data
  };
}
function exportBackup(){
  try{
    var obj=_backupObject();
    var name="casripos-backup-"+new Date().toISOString().slice(0,10)+".json";
    var blob=new Blob([JSON.stringify(obj,null,1)],{type:"application/json"});
    var url=URL.createObjectURL(blob);
    var a=document.createElement("a");
    a.href=url;a.download=name;document.body.appendChild(a);a.click();
    setTimeout(function(){URL.revokeObjectURL(url);a.remove();},400);
    toast(T("Backup saved: ","Kayd la keydiyay: ")+name);
  }catch(e){
    // Some WebViews block blob downloads — offer the raw text instead so the
    // user can still copy it out rather than losing the option entirely.
    igAlert(T("This device blocked the download. Copy the text below and save it yourself.",
              "Qalabkani wuu diiday soo dejinta. Koobi qoraalka hoose oo keydso.")+
            "\n\n"+JSON.stringify(_backupObject()),null,T("Backup","Kayd"));
  }
}
function openImport(){
  var f=$("bk_file");if(f)f.value="";
  var t=$("bk_t");if(t)t.textContent=T("Restore from backup","Ka soo celi kayd");
  var s=$("bk_s");if(s)s.textContent=T("This REPLACES everything on this device. Export a backup first if unsure.",
                                       "Tani way BEDDESHAA wax kasta oo qalabkan ku jira. Marka hore kayd samee haddaad shakisan tahay.");
  var c=$("bk_cancel");if(c)c.textContent=T("Cancel","Jooji");
  openM("M_backup");
}
function importBackupFile(input){
  var file=input&&input.files&&input.files[0];
  if(!file)return;
  var r=new FileReader();
  r.onload=async function(){
    var obj;
    try{obj=JSON.parse(r.result);}
    catch(e){toast(T("That file isn't a valid backup","Faylkaasi ma aha kayd sax ah"));return;}
    if(!obj||obj.app!=="CasriPOS"||!obj.data){
      toast(T("That file isn't a Casri POS backup","Faylkaasi ma aha kayd Casri POS"));return;
    }
    var when=obj.exportedAt?new Date(obj.exportedAt).toLocaleString():"?";
    var msg=T("Restore this backup?\n\n","Soo celi kaydkan?\n\n")+
            T("Made","La sameeyay")+": "+when+"\n"+
            (obj.businesses||0)+" "+T("businesses","ganacsi")+", "+
            (obj.products||0)+" "+T("products","alaab")+", "+
            (obj.sales||0)+" "+T("sales","iib")+"\n\n"+
            T("Everything currently on this device will be replaced.","Wax kasta oo hadda qalabkan ku jira waa la beddeli doonaa.");
    if(!await igAsk(msg,T("Restore","Soo celi")))return;
    try{
      Object.keys(obj.data).forEach(function(k){
        if(BACKUP_KEYS.indexOf(k)>=0)localStorage.setItem(k,obj.data[k]);
      });
    }catch(e){toast(T("Could not write the data","Xogta lama qori karin"));return;}
    closeM("M_backup");
    igAlert(T("Backup restored. The app will reload.","Kaydka waa la soo celiyay. Barnaamijku wuu dib u furmi doonaa."),
            function(){location.reload();});
  };
  r.readAsText(file);
}

// ============================================================
//  BARCODE LABELS — Code 128-B drawn as inline SVG.
//  Self-contained on purpose: the app is bundled offline, so pulling in a
//  barcode library would mean vendoring a file and trusting it. Code 128-B
//  covers every character a SKU or product code realistically uses.
// ============================================================
var _BC128=[
 "212222","222122","222221","121223","121322","131222","122213","122312","132212","221213",
 "221312","231212","112232","122132","122231","113222","123122","123221","223211","221132",
 "221231","213212","223112","312131","311222","321122","321221","312212","322112","322211",
 "212123","212321","232121","111323","131123","131321","112313","132113","132311","211313",
 "231113","231311","112133","112331","132131","113123","113321","133121","313121","211331",
 "231131","213113","213311","213131","311123","311321","331121","312113","312311","332111",
 "314111","221411","431111","111224","111422","121124","121421","141122","141221","112214",
 "112412","122114","122411","142112","142211","241211","221114","413111","241112","134111",
 "111242","121142","121241","114212","124112","124211","411212","421112","421211","212141",
 "214121","412121","111143","111341","131141","114113","114311","411113","411311","113141",
 "114131","311141","411131","211412","211214","211232","2331112"];
// Code 128-B is valid for ASCII 32..126 only.
function bcValid(s){s=String(s||"");if(!s)return false;for(var i=0;i<s.length;i++){var c=s.charCodeAt(i);if(c<32||c>126)return false;}return true;}
function _bc128Widths(text){
  var vals=[104],i;                                  // 104 = START B
  for(i=0;i<text.length;i++)vals.push(text.charCodeAt(i)-32);
  var sum=104;
  for(i=1;i<vals.length;i++)sum+=vals[i]*i;
  vals.push(sum%103);                                // checksum
  vals.push(106);                                    // STOP
  var w="";
  for(i=0;i<vals.length;i++)w+=_BC128[vals[i]];
  return w;
}
// Render as SVG: bars alternate starting with a bar, widths are module counts.
function bcSVG(text,mod,height){
  text=String(text||"");
  if(!bcValid(text))return "";
  mod=mod||2;height=height||38;
  var w=_bc128Widths(text),x=10*mod,bars="",isBar=true;   // 10-module quiet zone
  for(var i=0;i<w.length;i++){
    var n=parseInt(w.charAt(i),10)*mod;
    if(isBar)bars+="<rect x=\""+x+"\" y=\"0\" width=\""+n+"\" height=\""+height+"\"/>";
    x+=n;isBar=!isBar;
  }
  var total=x+10*mod;
  return "<svg class=\"bcSvg\" viewBox=\"0 0 "+total+" "+height+"\" width=\"100%\" height=\""+height+
         "\" preserveAspectRatio=\"xMidYMid meet\" shape-rendering=\"crispEdges\" role=\"img\" aria-label=\""+esc(text)+"\">"+
         "<rect width=\""+total+"\" height=\""+height+"\" fill=\"#fff\"/>"+bars+"</svg>";
}
// A product with no code can't be labelled. Give it a unique numeric one.
function _genBarcode(){
  var used={};forBiz(PRODUCTS).forEach(function(p){if(p.barcode)used[p.barcode]=1;});
  var base=Date.now()%100000;
  for(var i=0;i<100000;i++){
    var code=String(200000+((base+i)%800000));
    if(!used[code])return code;
  }
  return String(Date.now());
}
async function assignMissingBarcodes(){
  var missing=forBiz(PRODUCTS).filter(function(p){return !p.barcode&&!p.sku;});
  if(!missing.length){toast(T("Every product already has a code","Alaab kastaa waa leedahay lambar"));return;}
  if(!await igAsk(T("Give a barcode to ","Sii barcode ")+missing.length+T(" product(s) without one?"," alaabo oo aan lahayn?"),T("Generate","Samee")))return;
  missing.forEach(function(p){p.barcode=_genBarcode();});
  _save("pos_prod",PRODUCTS);
  toast(missing.length+" "+T("barcodes generated","barcode la sameeyay"));
  openLabels();
}
// ── Label sheet ─────────────────────────────────────────────
var LBL_QTY={};
function openLabels(){
  var list=forBiz(PRODUCTS);
  if(!list.length){toast(T("No products yet","Alaab ma jirto weli"));return;}
  var t=$("lbl_t");if(t)t.textContent=T("Print barcode labels","Daabac summadaha barcode");
  var s=$("lbl_s");if(s)s.textContent=T("Choose how many labels to print for each product.","Dooro immisa summad alaab kasta loo daabaco.");
  var g=$("lbl_gen");if(g)g.textContent=T("Generate codes for products without one","Samee lambar alaabta aan lahayn");
  var c=$("lbl_cancel");if(c)c.textContent=T("Close","Xir");
  var p=$("lbl_print");if(p)p.innerHTML="&#128424; "+T("Print","Daabac");
  var box=$("lbl_list");
  if(box){
    var h="";
    list.forEach(function(pr){
      var code=pr.barcode||pr.sku||"";
      var ok=bcValid(code);
      h+="<div class=\"lblRow\">";
      h+="<div class=\"lblNm\"><strong>"+(pr.icon||"&#128230;")+" "+esc(pr.name)+"</strong>";
      h+="<div class=\"lblCode\">"+(ok?esc(code):"<span style=\"color:#c62f16\">"+T("no code","lambar ma leh")+"</span>")+"</div></div>";
      h+="<input type=\"number\" min=\"0\" max=\"200\" value=\""+(LBL_QTY[pr.id]||0)+"\""+(ok?"":" disabled")+
         " onchange=\"LBL_QTY['"+pr.id+"']=parseInt(this.value)||0\">";
      h+="</div>";
    });
    box.innerHTML=h;
  }
  openM("M_labels");
}
function _labelHTML(pr,code){
  return "<div class=\"lbl\">"+
    "<div class=\"lblBiz\">"+esc(BIZ.name||"")+"</div>"+
    "<div class=\"lblPn\">"+esc(pr.name)+"</div>"+
    bcSVG(code,2,34)+
    "<div class=\"lblTxt\">"+esc(code)+"</div>"+
    "<div class=\"lblPr\">"+money(pr.price)+"</div>"+
  "</div>";
}
function printLabels(){
  var list=forBiz(PRODUCTS),cells=[],total=0;
  list.forEach(function(pr){
    var n=LBL_QTY[pr.id]||0;
    var code=pr.barcode||pr.sku||"";
    if(n>0&&bcValid(code)){for(var i=0;i<n;i++){cells.push(_labelHTML(pr,code));total++;}}
  });
  if(!total){toast(T("Set how many labels to print","Dooro immisa summad"));return;}
  var pa=$("printArea");
  if(!pa){pa=document.createElement("div");pa.id="printArea";document.body.appendChild(pa);}
  // labelMode stops the receipt's monospace print rule applying to labels
  pa.className="labelMode";
  pa.innerHTML="<div class=\"lblSheet\">"+cells.join("")+"</div>";
  try{window.print();}catch(e){toast(T("Printing not available here","Daabacaadu halkan ma shaqeyso"));}
}

// ============================================================
//  INVOICES — a formal printable document for a sale.
//  The receipt is the till slip; an invoice is the paperwork a business
//  customer files. Same sale, different presentation, so invoices are stored
//  as a thin record pointing at the sale rather than duplicating the items.
// ============================================================
var INVOICES=_load("pos_inv",[]);
var INV_FOR_SALE=null;   // sale awaiting invoice details
function _saveInv(){_save("pos_inv",INVOICES);}
function _invNo(inv){return "INV-"+String(inv.no).padStart(4,"0");}
// Per-business running number, so each shop's invoices read 0001, 0002…
function _nextInvNo(){
  var mine=INVOICES.filter(function(i){return i.bizId===CURRENT_BIZ_ID;});
  return mine.reduce(function(m,i){return Math.max(m,i.no||0);},0)+1;
}
function openInvoiceAsk(saleId){
  var s=SALES.find(function(x){return x.id===saleId&&x.bizId===CURRENT_BIZ_ID;});
  if(!s){toast(T("Sale not found","Iibka lama helin"));return;}
  var existing=INVOICES.find(function(i){return i.saleId===s.id;});
  if(existing){showInvoice(existing.id);return;}   // one invoice per sale
  INV_FOR_SALE=s;
  var t=$("inv_t");if(t)t.textContent=T("Create invoice","Samee qaansheeg");
  var sb=$("inv_s");if(sb)sb.textContent=T("A formal invoice document for this sale.","Qaansheeg rasmi ah oo iibkan ah.");
  [["inv_cn_l",T("Customer name","Magaca macmiilka")],["inv_cp_l",T("Phone (optional)","Telefoon (ikhtiyaari)")],
   ["inv_cd_l",T("Due date (optional)","Taariikhda bixinta (ikhtiyaari)")],["inv_ca_l",T("Address / notes (optional)","Cinwaan / xusuus (ikhtiyaari)")],
   ["inv_cancel",T("Cancel","Jooji")],["inv_make",T("Create invoice","Samee qaansheeg")]
  ].forEach(function(p){var e=$(p[0]);if(e)e.textContent=p[1];});
  ["inv_cn","inv_cp","inv_cd","inv_ca"].forEach(function(id){var e=$(id);if(e)e.value="";});
  openM("M_invask");
  setTimeout(function(){var e=$("inv_cn");if(e)e.focus();},60);
}
function createInvoice(){
  var s=INV_FOR_SALE;if(!s)return;
  var nm=($("inv_cn")&&$("inv_cn").value||"").trim();
  if(!nm){toast(T("Enter the customer name","Geli magaca macmiilka"));return;}
  var inv={
    id:"i"+Date.now(),
    bizId:CURRENT_BIZ_ID,
    no:_nextInvNo(),
    saleId:s.id,
    date:new Date().toISOString(),
    customer:nm,
    phone:($("inv_cp")&&$("inv_cp").value||"").trim(),
    due:($("inv_cd")&&$("inv_cd").value||"").trim(),
    addr:($("inv_ca")&&$("inv_ca").value||"").trim()
  };
  INVOICES.unshift(inv);_saveInv();
  INV_FOR_SALE=null;
  closeM("M_invask");
  toast(T("Invoice created","Qaansheeg la sameeyay"));
  showInvoice(inv.id);
}
function _invSale(inv){return SALES.find(function(x){return x.id===inv.saleId;})||null;}
function _invoiceHTML(inv){
  var s=_invSale(inv);
  if(!s)return "<div class=\"empty\">"+T("The sale for this invoice no longer exists.","Iibka qaansheegan lama helin.")+"</div>";
  var d=new Date(inv.date);
  var h="<div class=\"invHd\">";
  h+="<div class=\"invBiz\"><b>"+esc(BIZ.name||"Casri POS")+"</b>";
  if(BIZ.addr)h+="<span>"+esc(BIZ.addr)+"</span>";
  if(BIZ.phone)h+="<span>"+esc(BIZ.phone)+"</span>";
  h+="</div>";
  h+="<div class=\"invMeta\"><div class=\"lbl\">"+T("Invoice","Qaansheeg")+"</div>";
  h+="<div><b>"+_invNo(inv)+"</b></div>";
  h+="<div>"+T("Date","Taariikh")+": <b>"+d.toLocaleDateString()+"</b></div>";
  if(inv.due)h+="<div>"+T("Due","Bixinta")+": <b>"+esc(inv.due)+"</b></div>";
  h+="</div></div>";

  h+="<div class=\"invTo\"><div class=\"blk\"><div class=\"cap\">"+T("Bill to","Loo qoray")+"</div>";
  h+="<div class=\"nm\">"+esc(inv.customer)+"</div>";
  if(inv.phone)h+="<div class=\"ln\">"+esc(inv.phone)+"</div>";
  if(inv.addr)h+="<div class=\"ln\">"+esc(inv.addr)+"</div>";
  h+="</div><div class=\"blk\" style=\"text-align:right\"><div class=\"cap\">"+T("Served by","Waxaa adeegay")+"</div>";
  h+="<div class=\"ln\">"+esc(s.cashier||"-")+"</div>";
  h+="<div class=\"cap\" style=\"margin-top:8px\">"+T("Payment","Lacag bixinta")+"</div>";
  h+="<div class=\"ln\">"+esc(payLabel(s.payMethod||"cash"))+(s.payProvider?" ("+esc(s.payProvider)+")":"")+"</div>";
  h+="</div></div>";

  h+="<table class=\"invT\"><thead><tr><th>"+T("Description","Sharaxaad")+"</th>";
  h+="<th class=\"num\">"+T("Qty","Tirada")+"</th><th class=\"num\">"+T("Unit","Halkii")+"</th>";
  h+="<th class=\"num\">"+T("Amount","Qadarka")+"</th></tr></thead><tbody>";
  (s.items||[]).forEach(function(it){
    h+="<tr><td class=\"nm\">"+esc(it.name)+"</td><td class=\"num\">"+it.qty+"</td>";
    h+="<td class=\"num\">"+money(it.price)+"</td><td class=\"num\">"+money(it.price*it.qty)+"</td></tr>";
  });
  h+="</tbody></table>";

  h+="<div class=\"invSum\"><table><tr><td>"+T("Subtotal","Wadarta")+"</td><td>"+money(s.subtotal)+"</td></tr>";
  if(s.tax>0)h+="<tr><td>"+T("Tax","Canshuurta")+"</td><td>"+money(s.tax)+"</td></tr>";
  h+="<tr class=\"tot\"><td>"+T("TOTAL","WADARTA")+"</td><td>"+money(s.total)+"</td></tr></table></div>";
  h+="<div style=\"text-align:right\"><span class=\"invPaid\">&#10003; "+T("Paid","La bixiyay")+"</span></div>";
  h+="<div class=\"invFt\">"+T("Thank you for your business.","Mahadsanid ganacsigaaga.")+"</div>";
  return h;
}
var INV_OPEN=null;
function showInvoice(id){
  var inv=INVOICES.find(function(i){return i.id===id;});if(!inv)return;
  INV_OPEN=id;
  var t=$("invv_t");if(t)t.textContent=T("Invoice","Qaansheeg")+" "+_invNo(inv);
  var c=$("invv_close");if(c)c.textContent=T("Close","Xir");
  var p=$("invv_print");if(p)p.innerHTML="&#128424; "+T("Print","Daabac");
  var w=$("invv_wa");if(w)w.innerHTML="&#128241; "+T("WhatsApp","WhatsApp");
  var d=$("inv_doc");if(d)d.innerHTML=_invoiceHTML(inv);
  openM("M_inv");
}
function printInvoice(){
  var d=$("inv_doc");if(!d)return;
  // Print in page — window.open popups are blocked in the app's WebView.
  var pa=$("printArea");
  if(!pa){pa=document.createElement("div");pa.id="printArea";document.body.appendChild(pa);}
  pa.className="docMode";   // not the monospace receipt slip
  pa.innerHTML="<div class=\"invDoc\" style=\"border:none;padding:0\">"+d.innerHTML+"</div>";
  try{window.print();}catch(e){toast(T("Printing not available here","Daabacaadu halkan ma shaqeyso"));}
}
// Send the invoice as plain text — works even where printing doesn't.
function shareInvoiceWA(){
  var inv=INVOICES.find(function(i){return i.id===INV_OPEN;});if(!inv)return;
  var s=_invSale(inv);if(!s)return;
  var L=[];
  L.push("*"+(BIZ.name||"Casri POS")+"*");
  L.push(T("Invoice","Qaansheeg")+" "+_invNo(inv)+" — "+new Date(inv.date).toLocaleDateString());
  L.push(T("Bill to","Loo qoray")+": "+inv.customer);
  L.push("");
  (s.items||[]).forEach(function(it){L.push(it.name+"  "+it.qty+" x "+money(it.price)+"  = "+money(it.price*it.qty));});
  L.push("");
  if(s.tax>0)L.push(T("Subtotal","Wadarta")+": "+money(s.subtotal));
  if(s.tax>0)L.push(T("Tax","Canshuurta")+": "+money(s.tax));
  L.push("*"+T("TOTAL","WADARTA")+": "+money(s.total)+"*");
  var url="https://wa.me/"+(inv.phone||"").replace(/[^0-9]/g,"")+"?text="+encodeURIComponent(L.join("\n"));
  try{window.open(url,"_blank");}catch(e){toast(T("Could not open WhatsApp","WhatsApp lama furi karo"));}
}
async function delInvoice(id){
  var inv=INVOICES.find(function(i){return i.id===id;});if(!inv)return;
  if(!await igAsk(T("Delete invoice ","Tirtir qaansheegga ")+_invNo(inv)+"?"))return;
  INVOICES=INVOICES.filter(function(i){return i.id!==id;});
  _saveInv();renderPage("invoices");
  toast(T("Invoice deleted","Qaansheeg la tirtiray"));
}
PAGES.invoices=function(){
  var mine=INVOICES.filter(function(i){return i.bizId===CURRENT_BIZ_ID;});
  var tot=mine.reduce(function(a,i){var s=_invSale(i);return a+(s?s.total:0);},0);
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Invoices","Qaansheegyada")+"</div>";
  h+="<div class=\"phS\">"+esc(BIZ.name)+" &middot; "+mine.length+" "+T("invoices","qaansheeg")+" &middot; "+money(tot)+"</div></div></div>";
  h+="<div class=\"box\"><div class=\"bB\" style=\"padding:11px 16px;font-size:12px;color:#5c6b82\">";
  h+="&#128161; "+T("Make an invoice from any sale — open Sales History and press the invoice button.",
                   "Ka samee qaansheeg iib kasta — fur Taariikhda Iibka oo riix badhanka qaansheegga.")+"</div></div>";
  h+="<div class=\"box\"><table><thead><tr><th>"+T("No.","Lam.")+"</th><th>"+T("Date","Taariikh")+"</th>";
  h+="<th>"+T("Customer","Macmiilka")+"</th><th>"+T("Total","Wadarta")+"</th><th></th></tr></thead><tbody>";
  if(!mine.length){
    h+="<tr><td colspan=\"5\"><div class=\"empty\"><div class=\"emIc\">&#129534;</div>"+T("No invoices yet","Qaansheeg ma jiro weli")+"</div></td></tr>";
  } else {
    mine.forEach(function(i){
      var s=_invSale(i);
      h+="<tr><td><strong>"+_invNo(i)+"</strong></td>";
      h+="<td>"+new Date(i.date).toLocaleDateString()+"</td>";
      h+="<td><strong>"+esc(i.customer)+"</strong>"+(i.phone?"<div style=\"font-size:10px;color:#5c6b82\">"+esc(i.phone)+"</div>":"")+"</td>";
      h+="<td><strong style=\"color:#1152cc\">"+(s?money(s.total):"—")+"</strong></td>";
      h+="<td style=\"text-align:right;white-space:nowrap\">";
      h+="<button class=\"btn\" onclick=\"showInvoice('"+i.id+"')\">&#128065;</button> ";
      h+="<button class=\"btn btnR\" onclick=\"delInvoice('"+i.id+"')\">&#10005;</button></td></tr>";
    });
  }
  h+="</tbody></table></div>";
  return h;
};
function printReceipt(){
  // Print IN PAGE rather than via window.open — popups are blocked in the
  // Android WebView the APK runs in, so the old version silently did nothing.
  // #printArea is hidden on screen and is the only thing shown when printing.
  var txt=$("rec_body").textContent||"";
  if(!txt){toast(T("Nothing to print","Waxba lama daabici karo"));return;}
  var pa=$("printArea");
  if(!pa){pa=document.createElement("pre");pa.id="printArea";document.body.appendChild(pa);}
  pa.className="";          // plain monospace slip
  pa.textContent=txt;
  try{window.print();}
  catch(e){toast(T("Printing not available here","Daabacaadu halkan ma shaqeyso"));}
}

// ============================================================
//  PAGE: PRODUCTS
// ============================================================
var EDIT_PROD=null;
PAGES.products=function(){
  var bizProducts=forBiz(PRODUCTS);
  var h="<div class=\"ph\"><div><div class=\"phT\">"+T("Products","Alaabta")+"</div><div class=\"phS\">"+esc(BIZ.name)+" &middot; "+bizProducts.length+" "+T("items","alaabta")+"</div></div>";
  h+="<div class=\"phA\">";
  h+="<button class=\"btn\" onclick=\"openLabels()\">&#127991; "+T("Print labels","Daabac summado")+"</button>";
  h+="<button class=\"btn btnP\" onclick=\"openAddProduct()\">+ "+T("Add product","Ku dar alaab")+"</button>";
  h+="</div></div>";
  h+="<div class=\"box\"><table><thead><tr><th>"+T("Product","Alaabta")+"</th><th>"+T("Barcode / SKU","Barcode / SKU")+"</th><th>"+T("Category","Qaybta")+"</th><th>"+T("Price","Qiimaha")+"</th><th>"+T("Stock","Kayd")+"</th><th></th></tr></thead><tbody>";
  if(!bizProducts.length){h+="<tr><td colspan=\"6\"><div class=\"empty\"><div class=\"emIc\">&#128230;</div>"+T("No products yet","Alaab ma jirto weli")+"</div></td></tr>";}
  else{
    bizProducts.forEach(function(p){
      var stkBdg=p.stock<=0?"br":p.stock<=5?"ba":"bg";
      h+="<tr><td><strong>"+(p.icon||"&#128230;")+" "+esc(p.name)+"</strong></td>";
      h+="<td>"+(p.barcode?"<div style=\"font-family:ui-monospace,monospace;font-size:11.5px;color:#0a1628\">"+esc(p.barcode)+"</div>":"")+
         (p.sku?"<div style=\"font-size:10px;color:#5c6b82\">"+esc(p.sku)+"</div>":"")+
         (!p.barcode&&!p.sku?"<span style=\"color:#98a2b3\">—</span>":"")+"</td>";
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
  // SKU + barcode are available to EVERY business type now — a shop or cafe
  // sells barcoded bottled goods just like a retail store does.
  var rr=$("mp_retail_row");if(rr)rr.style.display="grid";
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
  var rr=$("mp_retail_row");if(rr)rr.style.display="grid";   // always available
  $("M_prod_t").textContent=T("Edit product","Wax ka beddel alaab");
  openM("M_prod");
}
function saveProduct(){
  var nm=$("mp_nm").value.trim();if(!nm){toast(T("Enter product name","Gali magaca alaabta"));return;}
  var pr=parseFloat($("mp_pr").value);if(isNaN(pr)||pr<0){toast(T("Invalid price","Qiimaha khalad"));return;}
  var stk=parseInt($("mp_stk").value);if(isNaN(stk)||stk<0)stk=0;
  var sku=$("mp_sku")?$("mp_sku").value.trim():"";
  var bc=$("mp_bc")?$("mp_bc").value.trim():"";
  // A barcode must be unique within the business, or scanning it is ambiguous
  // and would ring up whichever product happened to be found first.
  if(bc||sku){
    var clash=forBiz(PRODUCTS).find(function(x){
      if(x.id===EDIT_PROD)return false;
      return (bc&&(x.barcode||"").toLowerCase()===bc.toLowerCase())||
             (sku&&(x.sku||"").toLowerCase()===sku.toLowerCase());
    });
    if(clash){toast(T("Already used by ","Waxaa isticmaala ")+clash.name);return;}
  }
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
  var head="<th>"+T("Receipt","Risiidh")+"</th><th>"+T("Date","Taariikh")+"</th>";
  if(showTable)head+="<th>"+T("Table / Order","Miis / Dalbka")+"</th>";
  head+="<th>"+T("Items","Alaabta")+"</th><th>"+T("Paid by","Lacag bixin")+"</th><th>"+T("Cashier","Iibiyaha")+"</th><th>"+T("Total","Wadarta")+"</th><th></th>";
  h+="<div class=\"box\"><table><thead><tr>"+head+"</tr></thead><tbody>";
  var colspan=showTable?8:7;
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
      var _pm=s.payMethod||"cash";
      var _pc={cash:"bg",card:"bb",mobile:"ba"}[_pm]||"bgr";
      h+="<td><span class=\"bdg "+_pc+"\">"+esc(payLabel(_pm))+"</span>"+
         (s.payProvider?"<div style=\"font-size:10px;color:#5c6b82;margin-top:2px\">"+esc(s.payProvider)+"</div>":"")+"</td>";
      h+="<td>"+esc(s.cashier||"-")+"</td>";
      h+="<td><strong style=\"color:#1a6ef5\">"+money(s.total)+"</strong></td>";
      var _hasInv=INVOICES.find(function(i){return i.saleId===s.id;});
      h+="<td style=\"white-space:nowrap\"><button class=\"btn\" onclick=\"_viewSale('"+s.id+"')\" title=\""+T("Receipt","Risiidh")+"\">&#128424;</button> ";
      h+="<button class=\"btn"+(_hasInv?" btnP":"")+"\" onclick=\"openInvoiceAsk('"+s.id+"')\" title=\""+
         (_hasInv?T("View invoice","Eeg qaansheegga"):T("Create invoice","Samee qaansheeg"))+"\">&#129534;</button></td></tr>";
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
  h+=kpi(T("Lifetime sales","Iibka guud"),money(totalRev),"#1a6ef5",bizSales.length+" "+T("sales","la iibiyey"));
  h+=kpi(T("Avg sale","Celcelis"),money(bizSales.length?totalRev/bizSales.length:0),"#36b37e",null);
  h+=kpi(T("Products sold","Alaab la iibiyay"),topProds.reduce(function(a,p){return a+p.q;},0),"#6554c0",null);
  h+=kpi(T("SKUs","SKU"),bizProducts.length,"#ff991f",null);
  h+="</div>";
  // Takings split by how customers paid — tells you how much cash should be in
  // the drawer versus what landed in the bank / mobile-money account.
  var byPay={cash:{n:0,v:0},card:{n:0,v:0},mobile:{n:0,v:0}};
  bizSales.forEach(function(s){
    var m=s.payMethod||"cash";
    if(!byPay[m])byPay[m]={n:0,v:0};
    byPay[m].n++;byPay[m].v+=s.total;
  });
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#128179; "+T("Payment methods","Siyaabaha lacag bixinta")+"</div></div><div class=\"bB\">";
  if(!bizSales.length){h+="<div class=\"empty\">"+T("No sales yet","Iib ma jiro weli")+"</div>";}
  else{
    h+="<div style=\"display:flex;border-radius:6px;overflow:hidden;height:10px;margin-bottom:12px;background:#eef1f5\">";
    [["cash","#36b37e"],["card","#1a6ef5"],["mobile","#00b8d9"]].forEach(function(p){
      var pct=totalRev>0?(byPay[p[0]].v/totalRev*100):0;
      if(pct>0)h+="<div style=\"width:"+pct+"%;background:"+p[1]+"\"></div>";
    });
    h+="</div><table><thead><tr><th>"+T("Method","Habka")+"</th><th>"+T("Sales","Iibabka")+"</th><th style=\"text-align:right\">"+T("Amount","Lacagta")+"</th><th style=\"text-align:right\">%</th></tr></thead><tbody>";
    [["cash","#36b37e"],["card","#1a6ef5"],["mobile","#00b8d9"]].forEach(function(p){
      var d=byPay[p[0]],pct=totalRev>0?Math.round(d.v/totalRev*100):0;
      h+="<tr><td><span style=\"display:inline-block;width:9px;height:9px;border-radius:2px;background:"+p[1]+";margin-right:7px\"></span><strong>"+payLabel(p[0])+"</strong></td>";
      h+="<td>"+d.n+"</td><td style=\"text-align:right;font-weight:700\">"+money(d.v)+"</td>";
      h+="<td style=\"text-align:right;color:#5c6b82\">"+pct+"%</td></tr>";
    });
    h+="</tbody></table>";
  }
  h+="</div></div>";
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
      h+="<div class=\"bdg bgr\" style=\"margin-right:6px\">"+p.q+" "+T("sold","la iibiyey")+"</div>";
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
  h+="<div class=\"box\"><table><thead><tr><th>"+T("Name","Magaca")+"</th><th>"+T("Type","Nooca")+"</th><th>"+T("Currency","Lacagta")+"</th><th>"+T("Admins","Maamulayaal")+"</th><th>"+T("Products","Alaabta")+"</th><th>"+T("Sales","Iibabka")+"</th><th></th></tr></thead><tbody>";
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
  h+=T("Every business uses the SAME login page (this URL). Click ","Ganacsi kastaa wuxuu isticmaalaa sida bog gelitaanka. Riix ")+
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
  var user=await igAskText(T("Username (used to sign in)","Magaca isticmaalaha"));
  if(!user)return;
  if(ACCOUNTS.find(function(a){return a.username.toLowerCase()===user.toLowerCase();})){toast(T("Username already taken","Magaca waa la qaatay"));return;}
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
    "  "+T("Username","Magaca isticmaalaha")+": "+user+"\n"+
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
  var user=await igAskText(T("Username","Magaca isticmaalaha"));if(!user)return;
  if(ACCOUNTS.find(function(a){return a.username.toLowerCase()===user.toLowerCase();})){toast(T("Username taken","Magaca waa la qaatay"));return;}
  var pass=await igAskText(T("Password","Sirta"));if(!pass)return;
  var role=await igAsk(T("Make admin? (OK = admin, Cancel = cashier)","Maamulaha ka dhig?"))?"admin":"cashier";
  // Scope new accounts to a specific business. Default = active business.
  // Per-business admins always get their own business. Super-admin picks.
  var scope=CURRENT_USER.bizId||CURRENT_BIZ_ID;
  if(isSuperAdmin()){
    // A real dropdown of businesses. The old version printed a numbered list
    // into the prompt and asked the user to type the number — but HTML collapsed
    // the line breaks, so the list was unreadable and everyone ended up in
    // business #1 (the pre-filled default).
    var opts=BIZ_LIST.map(function(b){return {v:b.id,t:b.name};});
    opts.push({v:"__all__",t:"★ "+T("Super-admin (all businesses)","Maamule guud (dhammaan)")});
    var pick=await igAskChoice(
      T("Which business?","Ganacsi kee?"),
      T("This user will only see this business.","Isticmaalahani wuxuu arki doonaa ganacsigan oo kaliya."),
      opts, CURRENT_BIZ_ID);
    if(pick===null)return;
    if(pick==="__all__"){
      if(!await igAsk(T("This user will have super-admin access to ALL businesses. Are you sure?","Maamule guud oo ka shaqeeya DHAMMAAN ganacsiyada. Ma hubtaa?")))return;
      scope="";
    } else {
      scope=pick;
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
  var opts=BIZ_LIST.map(function(b){return {v:b.id,t:b.name};});
  opts.push({v:"__all__",t:"★ "+T("Super-admin (all businesses)","Maamule guud (dhammaan)")});
  var pick=await igAskChoice(
    T("Move ","U wareeji ")+a.name,
    T("Which business should this user belong to?","Ganacsi kee ayuu ka tirsanaan doonaa?"),
    opts, a.bizId||"__all__");
  if(pick===null)return;
  a.bizId=(pick==="__all__")?"":pick;
  _save("pos_acc",ACCOUNTS);renderPage("users");
  var scopeLbl=a.bizId?(BIZ_LIST.find(function(b){return b.id===a.bizId;})||{}).name:T("super-admin","maamule guud");
  toast(T("Moved → ","La wareejiyay → ")+scopeLbl);
}
async function _delAcc(id){
  var a=ACCOUNTS.find(function(x){return x.id===id;});if(!a)return;
  // Per-business admin can only delete users in their own business
  if(!isSuperAdmin()&&a.bizId!==CURRENT_USER.bizId){toast(T("Not allowed","Lama ogoolaan"));return;}
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

  // Cloud sync — keeps two devices in step and puts a copy off the device.
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#9729; "+T("Cloud sync","Isku xidhka cloud")+"</div>"+
     "<span id=\"cloudDot\"></span></div><div class=\"bB\" id=\"cloudBox\">"+_cloudSettingsHTML()+"</div></div>";
  // Backup / restore — the only protection against a lost or wiped device,
  // and the only way to move data between a PC and a phone.
  h+="<div class=\"box\"><div class=\"bH\"><div class=\"bT\">&#128190; "+T("Backup &amp; restore","Kayd &amp; soo celin")+"</div></div><div class=\"bB\">";
  h+="<div style=\"font-size:11px;color:#666;margin-bottom:9px\">"+
     T("Everything is stored on THIS device only. Export a backup regularly — if the phone is lost or reset, it is the only way to get your sales and products back. You can also import it on another device.",
       "Wax kastaa waxay ku kaydsan yihiin QALABKAN oo kaliya. Si joogto ah u samee kayd — haddii taleefanku lumo ama la nadiifiyo, kaydka oo kaliya ayaa iibkaaga iyo alaabtaada soo celin kara. Sidoo kale qalab kale ayaad ku soo celin kartaa.")+"</div>";
  h+="<div style=\"display:flex;gap:7px;flex-wrap:wrap\">";
  h+="<button class=\"btn btnP\" onclick=\"exportBackup()\">&#11015; "+T("Export backup","Samee kayd")+"</button>";
  h+="<button class=\"btn\" onclick=\"openImport()\">&#11014; "+T("Import backup","Soo celi kayd")+"</button>";
  h+="</div></div></div>";
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
async function _wipeProducts(){if(!await igAsk(T("Delete EVERY product in "+BIZ.name+"? Cannot be undone.","Tirtir DHAMMAAN alaabta "+BIZ.name+"?")))return;PRODUCTS=PRODUCTS.filter(function(p){return p.bizId!==CURRENT_BIZ_ID;});_save("pos_prod",PRODUCTS);toast(T("Products cleared","Alaabtii waa la cadeeyey"));renderPage("settings");}
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
async function _wipeSales(){if(!await igAsk(T("Delete ALL sales in "+BIZ.name+"? Cannot be undone.","Tirtir DHAMMAAN iibka "+BIZ.name+"?")))return;SALES=SALES.filter(function(s){return s.bizId!==CURRENT_BIZ_ID;});_save("pos_sales",SALES);toast(T("Cleared","waa la cadeeyey"));renderPage("settings");}

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
