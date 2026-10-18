import sys
from lupa import LuaRuntime
L=LuaRuntime(unpack_returned_tuples=True)
import os
base=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..')+os.sep
scenario=sys.argv[1] if len(sys.argv)>1 else "deux"
L.execute(r'''
unpack = unpack or table.unpack
local frames = {}
local Frame = {}
Frame.__index = function(t,k)
  if Frame[k] then return Frame[k] end
  if type(k)=='string' and (k:sub(1,1)=='_' or k=='TitleText' or k=='TitleContainer' or k=='Inset' or k=='natif') then return nil end
  return function(self, ...) return nil end
end
function Frame:GetStringWidth() return 60 end
function Frame:GetStringHeight() return 12 end
function Frame:GetWidth() return 100 end
function Frame:GetHeight() return 100 end
function Frame:IsShown() return self._shown == true end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:SetScript(n, fn) self._s = self._s or {} self._s[n] = fn end
function Frame:RegisterEvent(e) end
function Frame:CreateTexture() return setmetatable({}, Frame) end
function Frame:CreateFontString() local f=setmetatable({}, Frame) f._shown=true frames[#frames+1]=f return f end
function Frame:SetText(t) self._text = t end
function Frame:SetShown(b) self._shown = b and true or false end
function Frame:GetCenter() return 0,0 end
function Frame:GetLeft() return 10 end
function Frame:GetTop() return 10 end
function CreateFrame(kind, name, parent) local f = setmetatable({_shown=true, _name=name}, Frame) frames[#frames+1]=f if name then _G[name]=f end return f end
UIParent = CreateFrame("Frame","UIParent")
Minimap = CreateFrame("Frame","Minimap")
GameTooltip = setmetatable({lines={}}, Frame)
function GameTooltip:SetText(t) self.lines={t} end
function GameTooltip:AddLine(t) self.lines[#self.lines+1]=t end
SlashCmdList = {}
UISpecialFrames = {}
GetTime = function() return 0 end
IsShiftKeyDown = function() return false end
GetCursorPosition = function() return 0,0 end
UnitFactionGroup = function() return "Horde" end
ERR_LEARN_RECIPE_S = "Vous avez appris la recette %s."
printed = {}
print = function(...) local t={} for i,v in ipairs({...}) do t[#t+1]=tostring(v) end printed[#printed+1]=table.concat(t," ") end
_frames = frames
errs = {}
local _pc = pcall
pcall = function(f, ...) local r = table.pack(_pc(f, ...)) if not r[1] then errs[#errs+1] = tostring(r[2]) end return table.unpack(r, 1, r.n) end
''')
sc=sys.argv[1] if len(sys.argv)>1 else "deux"
if sc=="deux":
    L.execute(r'''
    local lignes = {{"Combat",true},{"Cuisine",false,0,95},{"Alchimie",false,0,143},{"Herboristerie",false,0,160},{"Épées",false,0,300}}
    GetNumSkillLines = function() return #lignes end
    GetSkillLineInfo = function(i) local l=lignes[i] return l[1], l[2], 0, l[4] end
    ''')
elif sc=="aucun":
    L.execute('GetNumSkillLines = function() return 0 end; GetSkillLineInfo=function() end')
# aucune API de compétences => tous affichés
L.execute(open(base+"Donnees.lua",encoding="utf-8").read())
L.execute(open(base+"Parcours.lua",encoding="utf-8").read())
L.execute(open(base+"Marchands.lua",encoding="utf-8").read())
ok=0;ko=0
def check(c,msg):
    global ok,ko
    if c: ok+=1
    else: ko+=1; print("ECHEC:",msg)
def run(code):
    return L.execute(code)
L.execute('''
local ev = nil
for _,f in ipairs(_frames) do if f._s and f._s.OnEvent and not ev then ev=f end end
_ev = ev
''')
run('_ev._s.OnEvent(_ev, "PLAYER_LOGIN")')
print("\n".join(L.eval("printed").values()))
# ouvrir le journal
run('SlashCmdList.PARCOURS("")')
fr=L.eval("ParcoursFrame")
check(fr._shown==True,"journal ouvert")
def tabs():
    return [ b for b in L.eval("(function() local r={} for _,f in ipairs(_frames) do if rawget(f,'id') and f._shown then local t=rawget(f,'texte') r[#r+1]= rawget(f,'id') end end return r end)()").values()]
print("onglets:",tabs())
if sc=="deux":
    check(tabs()==["Cuisine","Alchimie","Herboristerie"],"onglets = métiers appris")
else:
    check(len(tabs())==12,"tous les onglets si détection impossible")
run('SlashCmdList.PARCOURS("marchands")')
run('SlashCmdList.PARCOURS("marchands favoris")')
run('SlashCmdList.PARCOURS("etat")')
run('SlashCmdList.PARCOURS("suivi debug")')
run('SlashCmdList.PARCOURS("metier alchimie")')
run('SlashCmdList.PARCOURS("niveau 70")')
run('SlashCmdList.PARCOURS("recette connue")')
run('SlashCmdList.PARCOURS("tous")')
for m in ["cuisine","alchimie","forge","ingenierie","couture","cuir","enchantement","herboristerie","minage","depecage","secourisme","peche"]:
    run(f'SlashCmdList.PARCOURS("metier {m}")')
    run('SlashCmdList.PARCOURS("niveau 50")')
    run('SlashCmdList.PARCOURS("")') ; run('SlashCmdList.PARCOURS("")')
    # simuler un tick du suivi
    run('''
    for _,f in ipairs(_frames) do if f._name=="ParcoursSuivi" then f._s.OnUpdate(f, 2) f._s.OnUpdate(f, 2) end end
    ''')
out=L.eval("printed")
txt="\n".join(out.values())
check("erreur" not in txt.lower().replace("erreur (","ERR(") or True,"")
errs=[l for l in out.values() if "rreur" in l]
print("lignes d'erreur:",errs[:6])
check(len(errs)==0,"aucune erreur affichée")
pe=list(L.eval("errs").values()); print("erreurs pcall:",len(pe),pe[:5]); check(len(pe)==0,"aucune erreur interne")
L.execute('''
SlashCmdList.PARCOURS("metier alchimie") SlashCmdList.PARCOURS("niveau 70")
for _,f in ipairs(_frames) do if f._name=="ParcoursSuivi" then f._s.OnUpdate(f, 2) f._s.OnUpdate(f, 2) end end
dump = {}
for _,f in ipairs(_frames) do if f._text and f._shown and f._text ~= "" then dump[#dump+1] = f._text end end
''')
print("\n".join(list(L.eval("dump").values())[:60]))
print("\n".join(l for l in L.eval("printed").values() if "avori" in l or "Marchands" in l or "cmarch" in l)[:600]);print("ok",ok,"ko",ko)

# --- marqueurs de recettes (intégration) ---
L.execute("""
SlashCmdList.PARCOURS("metier cuisine") SlashCmdList.PARCOURS("niveau 45")
for _,f in ipairs(_frames) do if f._name=="ParcoursSuivi" then f._s.OnUpdate(f, 2) f._s.OnUpdate(f, 2) end end
printed2 = {}
local oldprint = print
print = function(m) printed2[#printed2+1]=tostring(m) end
SlashCmdList.CUISINEMARCHANDS("recettes")
SlashCmdList.PARCOURS("recette connue")
for _,f in ipairs(_frames) do if f._name=="ParcoursSuivi" then f._s.OnUpdate(f, 2) f._s.OnUpdate(f, 2) end end
SlashCmdList.CUISINEMARCHANDS("recettes")
print = oldprint
""")
print("MARQUEURS:", list(L.eval("printed2").values()))
