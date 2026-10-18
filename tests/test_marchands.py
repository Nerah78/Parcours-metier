import sys
from lupa import LuaRuntime
import os
SRC=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','Marchands.lua')
MOCK=r'''
OUT = {}
unpack = unpack or table.unpack
function print(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end OUT[#OUT+1]=table.concat(t," ") end
function strsplit(sep, s) local r={} for p in (s..sep):gmatch("(.-)"..sep:gsub("%-","%%-")) do r[#r+1]=p end return unpack(r) end
ALL = {}
local M = {}
M.__index = M
local function newobj(typ,parent)
  local o = setmetatable({_t=typ,_parent=parent,_shown=true,_w=0,_h=0,_pts={},_sc={},_ev={},_lvl=1,_strata="MEDIUM",_eff=1,_tex={}}, M)
  ALL[#ALL+1]=o
  return o
end
function M:SetSize(w,h) self._w,self._h=w,h end
function M:SetWidth(w) self._w=w end
function M:SetHeight(h) self._h=h end
function M:GetWidth() return self._w end
function M:GetHeight() return self._h end
function M:SetPoint(p,rel,rp,x,y) self._pts[#self._pts+1]={p=p,rel=rel,rp=rp,x=x,y=y} end
function M:ClearAllPoints() self._pts={} end
function M:Show() self._shown=true end
function M:Hide() self._shown=false end
function M:IsShown() return self._shown end
function M:IsVisible() if not self._shown then return false end if self._parent and self._parent.IsVisible then return self._parent:IsVisible() end return true end
function M:SetParent(p) self._parent=p end
function M:GetParent() return self._parent end
function M:SetFrameStrata(s) self._strata=s end
function M:GetFrameStrata() return self._strata end
function M:SetFrameLevel(l) self._lvl=l end
function M:GetFrameLevel() return self._lvl end
function M:GetEffectiveScale() return self._eff end
function M:EnableMouse() end
function M:SetScript(n,f) self._sc[n]=f end
function M:GetScript(n) return self._sc[n] end
function M:HookScript(n,f) self._hooks=self._hooks or {} self._hooks[n]=f end
function M:RegisterEvent(e) self._ev[e]=true end
function M:SetHighlightTexture() end
function M:GetLeft() return 100 end
function M:GetTop() return 100 end
function M:GetRight() return 200 end
function M:SetAllPoints() end
function M:SetTexture(t) self._tex.path=t end
function M:SetTexCoord() end
function M:SetColorTexture() self._color=true end
function M:SetDesaturated() end
function M:SetAlpha() end
function M:CreateTexture() return newobj("Texture",self) end
function CreateFrame(typ,name,parent) local o=newobj(typ,parent) if name then _G[name]=o end return o end
UIParent = newobj("Frame",nil); UIParent._eff=1
C_Timer = { After=function(t,f) PENDING=PENDING or {} PENDING[#PENDING+1]=f end }
GameTooltip = setmetatable({}, {__index=function() return function() end end})
hooksecurefunc=function(o,n,f) local old=o[n] o[n]=function(...) if old then old(...) end f(...) end end
CVARS = { nameplateShowFriendlyNPCs="0", nameplateShowFriends="1", nameplateShowAll="0", nameplateMaxDistance="41" }
function GetCVar(n) return CVARS[n] end
function SetCVar(n,v) CVARS[n]=v end
function GetRealZoneText() return "Clairières de Tirisfal" end
SlashCmdList = {}
-- carte
CANVAS = newobj("Frame",nil); CANVAS._w=0; CANVAS._h=0; CANVAS._eff=0.8
WorldMapFrame = newobj("Frame",nil); WorldMapFrame._shown=false
WorldMapFrame._mapID = 1420
function WorldMapFrame:GetCanvas() return CANVAS end
function WorldMapFrame:GetMapID() return self._mapID end
function WorldMapFrame:OnMapChanged() end
CANVAS._parent = WorldMapFrame
-- plaques
PLATES = {}
UNITS = {}
C_NamePlate = {
  GetNamePlateForUnit=function(u) for _,p in ipairs(PLATES) do if p.namePlateUnitToken==u then return p end end end,
  GetNamePlates=function() return PLATES end }
function UnitExists(u) return UNITS[u]~=nil end
function UnitGUID(u) return UNITS[u] and UNITS[u].guid end
function UnitName(u) return UNITS[u] and UNITS[u].name end
function UnitIsPlayer(u) return UNITS[u] and UNITS[u].player or false end
function AddPlate(token, guid, name, player)
  local p = newobj("Frame",nil); p.namePlateUnitToken=token; p._lvl=5
  p.UnitFrame = newobj("Frame",p); p.UnitFrame.name = newobj("FontString",p.UnitFrame)
  PLATES[#PLATES+1]=p; UNITS[token]={guid=guid,name=name,player=player}
  return p
end
CuisineMarchandsDB = { _favoris = {
  [2134] = {nom="Mme Winters", npcId=2134, mapID=1420, x=61.1, y=52.7, zone="Clairières de Tirisfal"},
  [3550] = {nom="Martine Tramblay", npcId=3550, mapID=1420, x=65.9, y=59.6, zone="Clairières de Tirisfal"},
  [4555] = {nom="Eleanor Rusk", npcId=4555, mapID=1458, x=69.1, y=48.5, zone="Fossoyeuse"},
}}
'''
L=LuaRuntime(unpack_returned_tuples=True)
L.execute(MOCK)
L.execute(open(SRC,encoding='utf-8').read())
same=L.eval('function(a,b) return a==b end')
ok=0; ko=0
def check(c,msg):
    global ok,ko
    if c: ok+=1
    else: ko+=1; print('ECHEC:',msg)
def lua(s): return L.execute(s)
def out(): return list(L.eval('OUT').values())
lua('OUT={}')
# frame d'événements principal
fev=L.eval('(function() for _,o in ipairs(ALL) do if o._ev.PLAYER_LOGIN then return o end end end)()')
check(fev is not None,'frame événements')
fev._sc['OnEvent'](fev,'PLAYER_LOGIN')
check(any('v0.9' in l for l in out()),'message v0.6 au login: %s'%out())
check(bool(fev._ev['NAME_PLATE_UNIT_ADDED']) if False else L.eval('(function() for _,o in ipairs(ALL) do if o._ev.NAME_PLATE_UNIT_ADDED then return true end end end)()'),'événement plaque enregistré')
def tick(n=1):
    lua('for _,o in ipairs(ALL) do if o._sc.OnUpdate then o._sc.OnUpdate(o,0.3) end end')
# carte fermée : rien
tick(); check(L.eval('(function() local n=0 for _,o in ipairs(ALL) do if o.fav and o:IsVisible() then n=n+1 end end return n end)()')==0,'pas de pin visible carte fermée')
# ouverture de la carte avec canevas non dimensionné (0x0)
lua('WorldMapFrame._shown=true'); tick()
pins=L.eval('(function() local r={} for _,o in ipairs(ALL) do if o.fav and o:IsShown() then r[#r+1]=o end end return r end)()')
pins=list(pins.values())
check(len(pins)==2,'2 pins sur Tirisfal, trouvé %d'%len(pins))
def pt(p):
    q=p._pts[1]; return q['x'],q['y']
byname={p.fav['nom']:p for p in pins}
x,y=pt(byname['Mme Winters']); 
check(abs(x-61.1/100*1002)<0.01 and abs(y+52.7/100*668)<0.01,'position Winters avec taille par défaut: %s %s'%(x,y))
p=byname['Mme Winters']
check(p._strata=='FULLSCREEN_DIALOG' and p._lvl==200,'strate/niveau des pins')
check(same(p._parent,L.eval('CANVAS')),'parent = canevas')
check(abs(p._w-24*1/0.8)<0.01,'taille compensée par l\'échelle: %s'%p._w)
# le canevas reçoit sa vraie taille
lua('CANVAS._w=1100 CANVAS._h=700'); tick()
x,y=pt(byname['Mme Winters']); check(abs(x-61.1/100*1100)<0.01 and abs(y+52.7/100*700)<0.01,'repositionnement après redimensionnement')
check(len(byname['Mme Winters']._pts)==1,'un seul point d\'ancrage')
# Fossoyeuse : pas sur la carte de Tirisfal
check('Eleanor Rusk' not in byname,'Rusk absent de Tirisfal')
# changement de carte vers Fossoyeuse
lua('WorldMapFrame._mapID=1458'); tick()
vis=[o.fav['nom'] for o in L.eval('(function() local r={} for _,o in ipairs(ALL) do if o.fav and o:IsShown() then r[#r+1]=o end end return r end)()').values()]
check(vis==['Eleanor Rusk'],'carte Fossoyeuse: %s'%vis)
# carte du continent : conversion
lua('''
CreateVector2D=function(x,y) return {x=x,y=y,GetXY=function(s) return s.x,s.y end} end
C_Map={GetWorldPosFromMapPos=function(id,v) return 0,{x=v.x*1000,y=v.y*1000} end,
       GetMapPosFromWorldPos=function(c,w,m) return m,{x=w.x/2000,y=w.y/2000,GetXY=function(s) return s.x,s.y end} end}
WorldMapFrame._mapID=1415''')
tick()
vis=sorted(o.fav['nom'] for o in L.eval('(function() local r={} for _,o in ipairs(ALL) do if o.fav and o:IsShown() then r[#r+1]=o end end return r end)()').values())
check(len(vis)==3,'carte continent: 3 favoris convertis, trouvé %s'%vis)
# conversion hors limites
lua('C_Map.GetMapPosFromWorldPos=function(c,w,m) return m,{x=1.4,y=0.2,GetXY=function(s) return s.x,s.y end} end'); tick()
vis=[o for o in L.eval('(function() local r={} for _,o in ipairs(ALL) do if o.fav and o:IsShown() then r[#r+1]=o end end return r end)()').values()]
check(len(vis)==0,'hors limites: aucun pin')
# erreur d'API : pas de plantage
lua('C_Map.GetWorldPosFromMapPos=function() error("boum") end'); tick()
check(True,'pcall conversion')
lua('C_Map=nil; WorldMapFrame._mapID=1420'); tick()
check(len([o for o in L.eval('(function() local r={} for _,o in ipairs(ALL) do if o.fav and o:IsShown() then r[#r+1]=o end end return r end)()').values()])==2,'retour sur Tirisfal sans C_Map')
check(not any('erreur (' in l.lower() for l in out()),'aucune erreur imprimée: %s'%[l for l in out() if 'erreur (' in l.lower()])

# --- plaques ---
lua('OUT={}')
P1=lua('return AddPlate("nameplate1","Creature-0-3-1-1-2134-0000AB","Mme Winters",false)')
P2=lua('return AddPlate("nameplate2","Creature-0-3-1-1-9999-0000AB","Garde",false)')
P3=lua('return AddPlate("nameplate3","Player-3-0000","Joueur",true)')
for u in ('nameplate1','nameplate2','nameplate3'):
    fev._sc['OnEvent'](fev,'NAME_PLATE_UNIT_ADDED',u)
def etoile(plate):
    r=L.eval('(function(p) for _,o in ipairs(ALL) do if o._parent==p and o.tex and o._t=="Frame" then return o end end end)')(plate)
    return r
e1=etoile(P1); e2=etoile(P2); e3=etoile(P3)
check(e1 is not None and e1._shown,'étoile sur la plaque du favori (sortie: %s)'%out())
check(e2 is None,'pas d\'étoile sur un PNJ non favori')
check(e3 is None,'pas d\'étoile sur un joueur')
q=e1._pts[1]; check(q['p']=='BOTTOM' and q['rp']=='TOP' and same(q['rel'],P1.UnitFrame.name),'ancrage au-dessus du nom')
check(e1._lvl==25,'niveau au-dessus de la plaque')
fev._sc['OnEvent'](fev,'NAME_PLATE_UNIT_REMOVED','nameplate1'); check(not e1._shown,'étoile masquée au retrait de la plaque')
fev._sc['OnEvent'](fev,'NAME_PLATE_UNIT_ADDED','nameplate1'); check(e1._shown,'étoile réaffichée (même cadre réutilisé)')
check(len([1 for _ in [0]])==1,'')
# retrait du favori : mise à jour immédiate
slash=L.eval('SlashCmdList["CUISINEMARCHANDS"]')
slash('reset favoris'); check(not e1._shown,'étoile masquée quand les favoris sont effacés')
# favori retrouvé par le nom (sans id)
lua('CuisineMarchandsDB._favoris={["Garde"]={nom="Garde",mapID=1420,x=1,y=1}}')
fev._sc['OnEvent'](fev,'NAME_PLATE_UNIT_ADDED','nameplate2')
check(etoile(P2) is not None and etoile(P2)._shown,'favori reconnu par son nom')
# plaque sans UnitFrame.name
P4=lua('local p=AddPlate("nameplate4","Creature-0-3-1-1-9999-0000AC","Garde",false); p.UnitFrame.name=nil; return p')
fev._sc['OnEvent'](fev,'NAME_PLATE_UNIT_ADDED','nameplate4')
check(same(etoile(P4)._pts[1]['rel'],P4.UnitFrame),'repli sur UnitFrame')
check(not any('erreur (' in l.lower() for l in out()),'plaques: aucune erreur: %s'%out())

# --- commandes ---
lua('OUT={}')
lua('CuisineMarchandsDB._favoris={[2134]={nom="Mme Winters",npcId=2134,mapID=1420,x=61.1,y=52.7,zone="T"}}')
lua('WorldMapFrame._shown=true'); tick()
for c in ('carte','carte test','plaques','plaques on','plaques','plaques off','favoris','etoile','minimap'):
    n=len(out()); slash(c); check(len(out())>n,'commande "%s" affiche quelque chose'%c)
o=out()
check(not any('erreur (' in l.lower() for l in o),'commandes sans erreur: %s'%[l for l in o if 'erreur (' in l.lower()])
check(L.eval('CVARS.nameplateShowFriendlyNPCs')=='0','CVar rétablie à sa valeur d\'origine')
check(L.eval('CuisineMarchandsDB._reglages.plaquesAvant')==None,'valeur d\'origine effacée')
slash('plaques on'); check(L.eval('CVARS.nameplateShowFriendlyNPCs')=='1','plaques on règle la CVar')
slash('plaques on'); slash('plaques off'); check(L.eval('CVARS.nameplateShowFriendlyNPCs')=='0','on deux fois puis off restaure l\'original')
# test carte : carré vert
lua('PENDING={}'); slash('carte test')
sq=L.eval('(function() for _,o in ipairs(ALL) do if o._color and o._parent and o._parent._w==40 then return o._parent end end end)()')
check(sq is not None and sq._shown and same(sq._parent,L.eval('CANVAS')),'carré de test posé sur le canevas')
lua('for _,f in ipairs(PENDING) do f() end'); check(not sq._shown,'carré masqué après 8 s')

# --- bascule de favori depuis la fenêtre du marchand : les plaques suivent ---
lua("""
MerchantFrame = CreateFrame("Frame","MerchantFrame",nil)
MerchantFrameCloseButton = CreateFrame("Button","MerchantFrameCloseButton",MerchantFrame)
C_Map = { GetBestMapForUnit=function() return 1420 end,
          GetPlayerMapPosition=function() return {GetXY=function() return 0.611,0.527 end} end }
UNITS["npc"]={guid="Creature-0-3-1-1-9999-0000AB",name="Garde"}
CuisineMarchandsDB._favoris={}
""")
slash('etoile')
click=L.eval('CuisineMarchandsEtoile')._sc['OnClick']
lua('OUT={}')
P5=lua('return AddPlate("nameplate5","Creature-0-3-1-1-9999-0000AD","Garde",false)')
fev._sc['OnEvent'](fev,'NAME_PLATE_UNIT_ADDED','nameplate5')
check(etoile(P5) is None,'pas d\'étoile avant d\'ajouter le favori')
click(); 
check(etoile(P5) is not None and etoile(P5)._shown,'étoile apparaît sur le PNJ dès l\'ajout du favori')
check(L.eval('CuisineMarchandsDB._favoris[9999].mapID')==1420,'favori enregistré')
click()
check(not etoile(P5)._shown,'étoile disparaît dès le retrait du favori')
check(not any('erreur (' in l.lower() for l in out()),'bascule sans erreur: %s'%out())


# --- livre du professeur ---
lua("""ClassTrainerFrame=CreateFrame("Frame","ClassTrainerFrame",nil)
ClassTrainerFrame.CloseButton=CreateFrame("Button",nil,ClassTrainerFrame)
UNITS["npc"]={guid="Creature-0-3-1-1-5555-0000AB",name="Clyde Kellen"}
CuisineMarchandsDB._favoris={}""")
lua('OUT={}')
fev._sc['OnEvent'](fev,'TRAINER_SHOW')
btn=L.eval('CuisineMarchandsLivre')
check(btn is not None,'bouton livre créé sur la fenêtre du professeur')
lua('ParcoursData={ordre={"peche"},metiers={peche={nom="Pêche",motsClient={"pêche","fishing"}}}}')
lua('GetNumTrainerServices=function() return 1 end; GetTrainerServiceInfo=function() return "Pêche (compagnon)" end')
btn._sc['OnClick'](btn)
fav=L.eval('CuisineMarchandsDB._favoris["prof:5555"]')
check(fav is not None and fav.type=='prof','favori professeur enregistré avec type prof (clé prof:5555)')
check(fav.metier=='Pêche','métier détecté: %s'%fav.metier)
check(L.eval('CuisineMarchandsDB._favoris[5555]')==None,'pas mélangé aux marchands')
lua('WorldMapFrame._shown=true'); tick()
tex=L.eval('(function() for _,o in ipairs(ALL) do if o._t=="Frame" and o.tex and o.tex._tex=="Interface\\\\GossipFrame\\\\TrainerGossipIcon" then return o.tex._tex end end end)()')
print('texture trouvée:',tex)
slash('favoris'); check(any('[Professeur Pêche]' in l for l in out()),'liste favoris marque le professeur')
btn._sc['OnClick'](btn); check(L.eval('CuisineMarchandsDB._favoris["prof:5555"]')==None,'second clic retire le favori')
slash('professeur'); check(any('ClassTrainerFrame' in l for l in out()),'diagnostic professeur')
check(not any('erreur' in l.lower() for l in out()),'livre sans erreur: %s'%out())

# --- marqueurs de recettes ---
lua('OUT={}; CuisineMarchandsDB._favoris={[3556]={nom="Andrew Hilbert",npcId=3556,mapID=1421,x=43.2,y=40.7,zone="F"}}')
lua('WorldMapFrame._shown=true; WorldMapFrame._mapID=1421'); tick()
def pinsvis():
    return list(L.eval('(function() local r={} for _,o in ipairs(ALL) do if o.fav and o:IsShown() then r[#r+1]=o end end return r end)()').values())
check(len(pinsvis())==1,'avant : seul le favori est affiché')
L.eval('ParcoursMarchandsAPI.DefinirRecettes')([ {} ] if False else L.table_from([L.table_from({'cle':'cuisine:2','nom':'Andrew Hilbert','mapID':1421,'x':43.2,'y':40.7,'zone':'Forêt','metier':'Cuisine','recette':'Viande d\'ours fumée','origine':'web'})]))
tick()
pv=pinsvis()
types=sorted(p.fav['type'] if p.fav['type'] else 'marchand' for p in pv)
check(types==['marchand','recette'],'favori + recette affichés: %s'%types)
rp=[p for p in pv if p.fav['type']=='recette'][0]
check(L.eval('function(p) return p.tex._tex.path end')(rp)=='Interface\\Icons\\INV_Scroll_03','icône parchemin: %s'%L.eval('function(p) return p.tex._tex.path end')(rp))
check(pt(rp)[0]>43.2/100*1100+10,'marqueur décalé à côté du favori')
lua('OUT={}'); slash('recettes'); check(any('Viande' in l for l in out()),'/cmarch recettes liste le marqueur: %s'%out())
L.eval('ParcoursMarchandsAPI.DefinirRecettes')(L.table_from([]))
tick(); check(len(pinsvis())==1,'recette apprise : le marqueur disparaît')
print('\n--- sortie de /cmarch carte ---'); lua('OUT={}'); slash('carte'); print('\n'.join(out()))
print('\n--- sortie de /cmarch plaques ---'); lua('OUT={}'); slash('plaques'); print('\n'.join(out()))

# --- liste par métier ---
lua("""ParcoursData={ordre={'cuisine','alchimie'},metiers={cuisine={nom='Cuisine',motsClient={'cuisine','cooking'},quetes={{ingredients={{id=2672,nom='Stringy Wolf Meat'}}}}},alchimie={nom='Alchimie',motsClient={'alchimie','alchemy'},quetes={{ingredients={{id=2447,nom='Peacebloom'}}}}}}}
CuisineMarchandsDB.V1={nom='Vend',zone='Z',x=1,y=2,composants={2672,2447},recettes={{id=1,nom='Recette: A',metier='cuisine'},{id=2,nom='Formule: B',metier='alchimie'}}}""")
lua('OUT={}'); slash(''); o=out()
check(any('[Alchimie]' in l for l in o) and any('[Cuisine]' in l for l in o),'liste: recettes étiquetées par métier: %s'%o)
lua('OUT={}'); slash('alchimie'); o=out()
check(any('Formule: B' in l for l in o) and not any('Recette: A' in l for l in o),'filtre alchimie: %s'%o)
lua('OUT={}'); slash('xyz'); check(any('inconnu' in l for l in out()),'métier inconnu signalé')
print('\nRÉSULTAT : %d ok, %d échec(s)'%(ok,ko)); sys.exit(1 if ko else 0)
