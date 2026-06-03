-- AutoParry v2.13 — 删除信心相关字段，保留v2.12其余全部优化
local Players=game:GetService("Players");local Workspace=game:GetService("Workspace");local UIS=game:GetService("UserInputService");local CoreGui=game:GetService("CoreGui");local VI=game:GetService("VirtualInputManager");local HttpService=game:GetService("HttpService");local TS=game:GetService("TweenService");local rootDir="ProjectAuto";local gameDir=rootDir.."/"..tostring(game.GameId or game.Name or "0")
local LP=Players.LocalPlayer;local pingSamples={};local currentPing=0
local STATE={LearningMode=false,AutoParry=false,ParryKey=Enum.KeyCode.F,KeyBindName="F",ConfThreshold=0.35,Active=true,UIVisToggleKey=Enum.KeyCode.RightShift,UIVisKeyName="RightShift",MaxRange=20,FacingCheck=false,FreezeOnLearn=false,AutoTiming=false}
local learnedAnims={};local recentAnims={};local activeAnims={};local trackedCharacters=setmetatable({},{__mode="k"});local lastParryTime={};local autoParryCooldown=0.1;local charCache={}
local folderExpanded={};local animExpanded={};local lockedSources={}
local blockedPrefixes={"walk","run","idle","jog","sprint","crouch","stand","getup","sit","lay","swim","climb","fall","freefall","slide","dodge","roll","shuffle","step","bounce","strafe","hover","float","fly","glide","turn","look","point","wave","dance","emote","nod","shake","breath","blink","flinch","stagger","aim","reload","laugh","cheer","cry"}

-- ====== 工具函数 ======
local function isBlocked(n)if not n then return true end;local l=n:lower();for _,p in ipairs(blockedPrefixes)do if l:find(p,1,true)then return true end end;return false end
local function getDist(c1,c2)if not c1 or not c2 then return 999 end;local p1=c1:FindFirstChild("HumanoidRootPart")or c1.PrimaryPart;local p2=c2:FindFirstChild("HumanoidRootPart")or c2.PrimaryPart;if not p1 or not p2 then return 999 end;return(p1.Position-p2.Position).Magnitude end
local function isFacing(c1,c2)if not c1 or not c2 then return false end;local r=c1:FindFirstChild("HumanoidRootPart")or c1.PrimaryPart;local t=c2:FindFirstChild("HumanoidRootPart")or c2.PrimaryPart;if not r or not t then return false end;return r.CFrame.LookVector:Dot((t.Position-r.Position).Unit)>0.2 end
local function clamp(v,mn,mx)return math.max(mn,math.min(mx,v))end
local function median(t)
	local n=#t;if n==0 then return 0.5 end
	local s={};for i=1,n do s[i]=t[i]end;table.sort(s)
	local m=math.floor(n/2);return n%2==0 and(s[m]+s[m+1])/2 or s[m+1]
end
local function getSN(c)if not c then return nil end;local p=Players:GetPlayerFromCharacter(c);return p and p.Name or c.Name end
local function getST(c)if not c then return"NPC"end;if type(c)=="string"then return(Players:FindFirstChild(c)and"Player"or"NPC")end;return(Players:GetPlayerFromCharacter(c)and"Player"or"NPC")end
-- 缓存 getSP 结果避免反复 pcall
local _spCached=nil
local function getSP()
	if _spCached and _spCached.Parent then return _spCached end
	local ok=pcall(function()local t=Instance.new("ScreenGui");t.Parent=CoreGui;t:Destroy()end)
	_spCached=ok and CoreGui or(LP and LP:FindFirstChild("PlayerGui"))or(LP and LP:WaitForChild("PlayerGui",5))
	return _spCached
end
local attackKeywords={"attack","slash","punch","kick","hit","swing","combo","strike","smash","bash","cut","stab","shoot","fire","blast","beam","claw","bite","spin","uppercut"}
local function nameScore(n)if not n or n==""then return 0 end;local l=n:lower();for _,k in ipairs(attackKeywords)do if l:find(k)then return 0.25 end end;return 0 end

-- ====== 持久化 ======
local function saveSource(sn)
	local ok,err=pcall(function()
		local data={}
		for aid,a in pairs(learnedAnims)do
			if a.sourceName==sn then
				data[aid]={n=a.name,av=a.avgTiming,ho=a.hold,en=a.enabled,lo=a.locked,tl=a.timingLocked,sc=a.seenCount,ah=a.attackHits,pc=a.parryCount,le=a.length,tn={}}
				for _,t in ipairs(a.timings)do table.insert(data[aid].tn,t)end
			end
		end
		if next(data)then writefile(gameDir.."/"..sn..".json",HttpService:JSONEncode(data))end
	end)
	if not ok then warn("[AP]保存失败:",sn,err)end
end
local function delSource(sn)
	pcall(function()delfile(gameDir.."/"..sn..".json")end)
end
local function saveKW()
	local ok,err=pcall(function()
		writefile(gameDir.."/Keywords.json",HttpService:JSONEncode({bp=blockedPrefixes,ak=attackKeywords}))
	end)
	if not ok then warn("[AP]关键词保存失败:",err)end
end
local function loadKW()
	local ok,err=pcall(function()
		local rOk,raw=pcall(readfile,gameDir.."/Keywords.json");if not rOk or not raw or raw==""then return end
		local data=HttpService:JSONDecode(raw);if not data then return end
		if data.bp and #data.bp>0 then for _,v in ipairs(data.bp)do local found=false;for _,k in ipairs(blockedPrefixes)do if k==v then found=true;break end end;if not found then table.insert(blockedPrefixes,v)end end end
		if data.ak and #data.ak>0 then for _,v in ipairs(data.ak)do local found=false;for _,k in ipairs(attackKeywords)do if k==v then found=true;break end end;if not found then table.insert(attackKeywords,v)end end end
	end)
	if not ok then warn("[AP]关键词读取失败:",err)end
end
local function saveSettings()
	local ok,err=pcall(function()
		local lk={};for sn in pairs(lockedSources)do lk[#lk+1]=sn end
		local gData={UV=STATE.UIVisKeyName or"RightShift",MR=STATE.MaxRange,Fa=STATE.FacingCheck,Fr=STATE.FreezeOnLearn,AT=STATE.AutoTiming,LK=lk}
		writefile(rootDir.."/GlobalSettings.json",HttpService:JSONEncode(gData))
		local pData={PK=STATE.KeyBindName or"F"}
		writefile(gameDir.."/KeyBindings.json",HttpService:JSONEncode(pData))
	end)
	if not ok then warn("[AP]设置保存失败:",err)end
end
local function loadSettings()
	local ok,err=pcall(function()
		local gOk,gRaw=pcall(readfile,rootDir.."/GlobalSettings.json");if gOk and gRaw and gRaw~=""then
			local gData=HttpService:JSONDecode(gRaw)
			if gData then
				if gData.UV then STATE.UIVisKeyName=gData.UV end
				if gData.MR then STATE.MaxRange=gData.MR end
				if gData.Fa~=nil then STATE.FacingCheck=gData.Fa end
				if gData.Fr~=nil then STATE.FreezeOnLearn=gData.Fr end
				if gData.AT~=nil then STATE.AutoTiming=gData.AT end
				if gData.LK and type(gData.LK)=="table"then for _,sn in ipairs(gData.LK)do lockedSources[sn]=true end end
			end
		end
		local pOk,pRaw=pcall(readfile,gameDir.."/KeyBindings.json");if pOk and pRaw and pRaw~=""then
			local pData=HttpService:JSONDecode(pRaw)
			if pData and pData.PK then
				local kc=Enum.KeyCode[pData.PK]
				if kc then STATE.ParryKey=kc;STATE.KeyBindName=pData.PK end
			end
		end
	end)
	if not ok then warn("[AP]设置读取失败:",err)end
end
local function saveAll()
	for sn in pairs(learnedAnims)do
		local has=false;for _,a in pairs(learnedAnims)do if a.sourceName==sn then has=true;break end end
		if has then saveSource(sn)end
	end
	saveKW();saveSettings()
end
local function loadAll()
	local ok,err=pcall(function()
		local files=listfiles(gameDir.."/");if type(files)~="table"then return end
		-- 收集所有加载的 AnimationId 用于级联匹配
		local loadedAids={}
		local parsedFiles={}
		for _,f in ipairs(files)do
			local fn=f:match("([^/\\]+)%.json$");if not fn or fn=="Keywords"or fn=="KeyBindings"then continue end
			local rOk,raw=pcall(readfile,f);if not rOk or not raw or raw==""then continue end
			local data=HttpService:JSONDecode(raw);if not data then continue end
			parsedFiles[f]=data
			for aid,a in pairs(data)do
				if not learnedAnims[aid]then
					learnedAnims[aid]={name=a.n,sourceName=fn,sourceType=a.st or"NPC",seenCount=a.sc or 0,parryCount=a.pc or 0,attackHits=a.ah or 0,timings=a.tn or{},avgTiming=a.av or 0.5,hold=a.ho or 0.08,enabled=a.en,locked=a.lo,timingLocked=a.tl,length=a.le or 1}
					loadedAids[aid]=true
				end
			end
		end
		-- AnimationId 级联匹配：跨游戏时同一动画不同 sourceName（缓存了 parsedFiles，不再读第二遍）
		if next(loadedAids)then
			for f,data in pairs(parsedFiles)do
				for aid,a in pairs(data)do
					if learnedAnims[aid]then
						if learnedAnims[aid].sourceName~=fn and learnedAnims[aid].attackHits<(a.ah or 0)then
							-- 跨游戏相同动画，信任数据更多的那个
							learnedAnims[aid].sourceName=fn
						end
					end
				end
			end
		end
	end)
	if not ok then warn("[AP]数据读取失败:",err)end
	loadKW()
end

E={}

-- ====== 学习条目工厂 ======
local function newLA(name,src,st,len)
	return{name=name,sourceName=src,sourceType=st,seenCount=0,parryCount=0,attackHits=0,timings={},avgTiming=0.5,hold=0.08,enabled=true,locked=false,timingLocked=false,length=len or 1}
end
local function getLA(aid,an,sn,st,al)
	if not learnedAnims[aid]and STATE.LearningMode then learnedAnims[aid]=newLA(an,sn,st,al)end;return learnedAnims[aid]
end
local function isConfirmed(a)return a and(a.attackHits>0 or a.parryCount>0 or a.seenCount>=5 or(STATE.LearningMode and a.seenCount>0))end

-- BuildTree debounce
local buildTreeTimer=nil
local function debounceBuildTree()
	if buildTreeTimer then task.cancel(buildTreeTimer)end
	buildTreeTimer=task.delay(0.3,function()
		buildTreeTimer=nil
		if E.BuildTree then E:BuildTree()end
	end)
end

-- ====== 自动格挡（含 ping 补偿 + per-source cooldown） ======
local function autoParry(animTrack,la,sn,an)
	local now=os.clock()
	local last=lastParryTime[sn]or 0;if now-last<autoParryCooldown then return end;lastParryTime[sn]=now
	if not STATE.ParryKey then return end
	local delay=clamp((la.avgTiming or 0.5)*(la.length or 1)-0.02-(currentPing/2000),0,2)
	task.delay(delay,function()
		if not STATE.Active or not STATE.AutoParry or not STATE.ParryKey then return end
		VI:SendKeyEvent(true,STATE.ParryKey,false,nil);task.wait(la.hold or 0.08);VI:SendKeyEvent(false,STATE.ParryKey,false,nil)
		task.spawn(function()local c=LP.Character;if not c then return end;local h=c:FindFirstChildOfClass("Humanoid");if not h then return end;pcall(function()h:SetStateEnabled(Enum.HumanoidStateType.Block,true)end)end)
	end)
end

-- ====== 受伤害回溯（事件驱动，精确到帧） ======
local lastHealth=nil
local function onHit(now,char)
	if not STATE.Active then return end
	local closestSn=nil;local closestDist=999
	for sn,_ in pairs(recentAnims)do
		local srcChar=charCache[sn]
		if not srcChar or not srcChar:FindFirstChildOfClass("Humanoid")then
			local pObj=Players:FindFirstChild(sn)
			if pObj then srcChar=pObj.Character;charCache[sn]=srcChar end
		end
		local dist=srcChar and getDist(srcChar,char)or 999
		if dist<closestDist then closestDist=dist;closestSn=sn end
	end
	local function markAnims(sn,anims,dist)
		if lockedSources[sn]then return end
		for _,entry in ipairs(anims)do
			local age=now-entry.time;if age>0.8 then continue end
			local r=STATE.MaxRange
			local tw=clamp(1-math.abs(age-0.5)/0.5,0,1)*0.5+0.3
			local dw=clamp(1-(dist/r),0,1)*0.3+0.4
			local sc=tw*dw;if sc<0.3 then continue end
			local la=getLA(entry.aid,entry.an,sn,getST(sn),entry.len)
			if not la then if not STATE.LearningMode then continue end;la=newLA(entry.an,sn,getST(sn),entry.len);la.attackHits=sc;learnedAnims[entry.aid]=la end
			if not la.locked then la.attackHits=la.attackHits+sc;la.seenCount=math.max(la.seenCount,la.attackHits+la.parryCount)end
			if STATE.AutoTiming and not la.timingLocked and(la.attackHits>0 or la.parryCount>0 or nameScore(entry.an)>0)then
				local timing=clamp(age/math.max(entry.len,0.01),0,1)
				if timing>0.75 then continue end
				table.insert(la.timings,timing);while #la.timings>20 do table.remove(la.timings,1)end;la.avgTiming=median(la.timings)
				if #la.timings>=12 then la.timingLocked=true end
			end
		end
	end
	if closestSn and closestDist<=STATE.MaxRange then
		local anims=recentAnims[closestSn];if anims then markAnims(closestSn,anims,closestDist)end
	else
		for sn,anims in pairs(recentAnims)do
			local srcChar=charCache[sn]
			if not srcChar or not srcChar:FindFirstChildOfClass("Humanoid")then
				local pObj=Players:FindFirstChild(sn)
				if pObj then srcChar=pObj.Character;charCache[sn]=srcChar
				else
					for _,o in ipairs(Workspace:GetDescendants())do if o:IsA("Model")and o.Name==sn and o:FindFirstChildOfClass("Humanoid")then srcChar=o;charCache[sn]=srcChar;break end end
				end
			end
			local dist=srcChar and getDist(srcChar,char)or 999
			if dist<=STATE.MaxRange then markAnims(sn,anims,dist)end
		end
	end
	debounceBuildTree()
end
local function setupHealthMonitor(char)
	if not char then return end
	local hum=char:FindFirstChildOfClass("Humanoid")
	if not hum then task.delay(0.5,function()setupHealthMonitor(char)end)return end
	lastHealth=hum.Health
	hum.HealthChanged:Connect(function(newHealth)
		if not STATE.Active then return end
		if lastHealth and newHealth<lastHealth-0.5 and newHealth>0 then onHit(os.clock(),char)end
		lastHealth=newHealth
	end)
end
setupHealthMonitor(LP.Character)
LP.CharacterAdded:Connect(setupHealthMonitor)


coroutine.wrap(function()
	while true do
		task.wait(1)
		local now=os.clock()
		for aid,data in pairs(activeAnims)do
			if now-data.startTime>data.length+0.5 then
				activeAnims[aid]=nil
			end
		end
	end
end)()

-- ====== 动画监控 ======
local function onAP(char,humanoid,animTrack)
	if not STATE.Active then return end;local sn=getSN(char);if not sn then return end;local st=getST(char);charCache[sn]=char
	local anim=animTrack.Animation;if not anim then return end;local aid=anim.AnimationId or"";local an=anim.Name or"";local al=animTrack.Length or 1;if aid==""then return end
	if isBlocked(an)then return end
	local myChar=LP.Character;if not myChar then return end
	if getDist(myChar,char)>STATE.MaxRange then return end
	if STATE.FacingCheck and not isFacing(char,myChar)then return end
	local now=os.clock()
	if activeAnims[aid]and now-activeAnims[aid].startTime<0.05 then return end
	activeAnims[aid]={startTime=now,length=al,sourceName=sn,animName=an}
	if not recentAnims[sn]then recentAnims[sn]={}end;table.insert(recentAnims[sn],{time=now,aid=aid,an=an,len=al})
	if #recentAnims[sn]>60 then
		local cutoff=os.clock()-5
		local keepStart=1
		for i=1,#recentAnims[sn]do
			if recentAnims[sn][i].time>=cutoff then keepStart=i;break end
			keepStart=i+1
		end
		if keepStart>1 then
			local newLen=#recentAnims[sn]-keepStart+1
			for i=1,newLen do
				recentAnims[sn][i]=recentAnims[sn][i+keepStart-1]
			end
			for i=1,keepStart-1 do recentAnims[sn][newLen+i]=nil end
		end
	end
	local skipLearn=lockedSources[sn]
	if STATE.AutoParry or(STATE.LearningMode and not skipLearn)then
		local la=getLA(aid,an,sn,st,al)
		if la then
		if not skipLearn and not la.locked and not(STATE.FreezeOnLearn and la.attackHits>0)then
			la.seenCount+=1;la.length=al
			if la.attackHits==0 and la.parryCount==0 and la.seenCount>=2 and nameScore(an)>0 then la.attackHits=1 end
		end
		if STATE.AutoParry and la.enabled then
			local total=la.attackHits+la.parryCount
			if total>0 or la.seenCount>=5 then autoParry(animTrack,la,sn,an)end
		end
		end
	end
end

-- ====== 角色追踪（tryTrack 加最大重试次数） ======
local function trackChar(char)if not char or trackedCharacters[char]then return end;trackedCharacters[char]=true;local h=char:FindFirstChildOfClass("Humanoid");if not h then task.delay(1,function()local h2=char:FindFirstChildOfClass("Humanoid");if h2 then trackChar(char)end end)return end;h.AnimationPlayed:Connect(function(t)onAP(char,h,t)end)end
local function trackAll()for _,p in ipairs(Players:GetPlayers())do if p~=LP then if p.Character then trackChar(p.Character)end;p.CharacterAdded:Connect(trackChar)end end;Players.PlayerAdded:Connect(function(p)if p~=LP then p.CharacterAdded:Connect(trackChar);if p.Character then trackChar(p.Character)end end end);Players.PlayerRemoving:Connect(function(p)recentAnims[p.Name]=nil;charCache[p.Name]=nil;for aid,a in pairs(activeAnims)do if a.sourceName==p.Name then activeAnims[aid]=nil end end;if p.Character then trackedCharacters[p.Character]=nil end end)end
local function scanExistingNPCs()
	local all=Workspace:GetDescendants();local i=1
	while i<=#all do
		for _=1,20 do if i>#all then break end;local o=all[i];i+=1
			if o:IsA("Model")and o:FindFirstChildOfClass("Humanoid")and not Players:GetPlayerFromCharacter(o)and not trackedCharacters[o]then trackChar(o)end
		end
		task.wait()
	end
end
local function tryTrack(obj,retries)
	if not retries then retries=0 end;if retries>=3 then return end
	if obj:IsA("Model")and not Players:GetPlayerFromCharacter(obj)and not trackedCharacters[obj]then
		if obj:FindFirstChildOfClass("Humanoid")then trackChar(obj)else task.delay(1,function()tryTrack(obj,retries+1)end)end
	end
end
Workspace.DescendantAdded:Connect(tryTrack)

-- ====== 玩家格挡→学习 ======
local function onPlayerParry()
	if not STATE.Active or not STATE.LearningMode then return end;local now=os.clock();local matched={}
	for aid,active in pairs(activeAnims)do
		local a=learnedAnims[aid];if a and a.locked then continue end
		if not active or not active.startTime then continue end;local elapsed=now-active.startTime
		if elapsed<0 or elapsed>active.length then continue end;if isBlocked(active.animName)then continue end
		if not active.animName then continue end
		local timing=clamp(elapsed/math.max(active.length,0.01),0,1);if timing>0.75 then continue end
		local la=getLA(aid,active.animName,active.sourceName,getST(active.sourceName),active.length)
		if la.locked then continue end;la.parryCount+=1
		if not la.timingLocked then table.insert(la.timings,timing);while #la.timings>20 do table.remove(la.timings,1)end;la.avgTiming=median(la.timings);if #la.timings>=12 then la.timingLocked=true end end
		matched[#matched+1]={s=active.sourceName,a=active.animName}
	end
	if #matched>0 then debounceBuildTree()end
end

-- ====== 定期清理 NPC 过期来源（修复暂停后协程退出） ======
coroutine.wrap(function()
	while true do
		task.wait(30)
		if STATE.Active then
			local myChar=LP.Character;if not myChar then return end
			for sn in pairs(recentAnims)do
				local srcChar=charCache[sn]
				if srcChar and getDist(srcChar,myChar)>STATE.MaxRange*3 then
					recentAnims[sn]=nil
				end
			end
		end
	end
end)()

-- ====== UI ======
local function ui(cn,p,c)local i=Instance.new(cn);for k,v in pairs(p or{})do i[k]=v end;for _,ch in ipairs(c or{})do ch.Parent=i end;return i end
local function lbl(t,ex)local p={Text=t,Font=Enum.Font.SourceSansBold,TextSize=13,TextColor3=Color3.fromRGB(225,225,235),BackgroundTransparency=1,BorderSizePixel=0};if ex then for k,v in pairs(ex)do p[k]=v end end;return ui("TextLabel",p)end
local function cr(r)return ui("UICorner",{CornerRadius=UDim.new(0,r or 4)})end

local sg=ui("ScreenGui",{Name="APUI",ZIndexBehavior=Enum.ZIndexBehavior.Sibling,ResetOnSpawn=false,Parent=getSP()})
local win=ui("ImageButton",{Name="Main",Size=UDim2.new(0,460,0,580),Position=UDim2.new(0,30,0,70),BackgroundColor3=Color3.fromRGB(22,24,30),BorderSizePixel=1,BorderColor3=Color3.fromRGB(40,42,50),Active=true,AutoButtonColor=false,ImageTransparency=1,Parent=sg});cr(14).Parent=win
local title=ui("Frame",{Size=UDim2.new(1,0,0,44),BackgroundColor3=Color3.fromRGB(26,28,34),BorderSizePixel=0,Parent=win});cr(14).Parent=title
lbl("Project Auto",{Position=UDim2.new(0,18,0,0),Size=UDim2.new(1,-20,1,0),TextXAlignment=Enum.TextXAlignment.Left,TextSize=15,TextColor3=Color3.fromRGB(255,255,255),Font=Enum.Font.GothamSemibold,Parent=title})
lbl("v2.13",{Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,-18,1,0),TextXAlignment=Enum.TextXAlignment.Right,TextSize=11,TextColor3=Color3.fromRGB(100,105,115),Parent=title})
local dragging=false;local ds;local fs
title.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true;ds=i.Position;fs=win.Position;i.Changed:Connect(function()if i.UserInputState==Enum.UserInputState.End then dragging=false end end)end end)
UIS.InputChanged:Connect(function(i)if dragging and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;win.Position=UDim2.new(0,fs.X.Offset+d.X,0,fs.Y.Offset+d.Y)end end)

local body=ui("Frame",{Size=UDim2.new(1,-16,1,-52),Position=UDim2.new(0,8,0,44),BackgroundTransparency=1,Parent=win})
local sBg=ui("Frame",{Size=UDim2.new(1,0,0,78),BackgroundColor3=Color3.fromRGB(26,28,34),BorderSizePixel=1,BorderColor3=Color3.fromRGB(40,42,50),Parent=body});cr(10).Parent=sBg
local function mkTg(l,x,g,s)
	local g2=ui("Frame",{Size=UDim2.new(0,160,0,28),Position=UDim2.new(0,x,0,4),BackgroundTransparency=1,Parent=sBg})
	lbl(l,{Position=UDim2.new(0,0,0,0),Size=UDim2.new(0,72,1,0),TextXAlignment=Enum.TextXAlignment.Left,TextSize=12,TextColor3=Color3.fromRGB(175,178,185),Font=Enum.Font.GothamSemibold,Parent=g2})
	local sw=ui("ImageButton",{Size=UDim2.new(0,44,0,24),Position=UDim2.new(0,110,0,2),BackgroundColor3=Color3.fromRGB(55,55,60),BorderSizePixel=0,Parent=g2,Active=true,AutoButtonColor=false});cr(12).Parent=sw
	local knob=ui("Frame",{Size=UDim2.new(0,20,0,20),Position=UDim2.new(0,2,0,2),BackgroundColor3=Color3.fromRGB(220,220,225),BorderSizePixel=0,Parent=sw});cr(10).Parent=knob
	local function ref(a)
		if g()then
			if a then TS:Create(sw,TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundColor3=Color3.fromRGB(48,140,80)}):Play();TS:Create(knob,TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0,22,0,2)}):Play()
			else sw.BackgroundColor3=Color3.fromRGB(48,140,80);knob.Position=UDim2.new(0,22,0,2)end
		else
			if a then TS:Create(sw,TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundColor3=Color3.fromRGB(55,55,60)}):Play();TS:Create(knob,TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0,2,0,2)}):Play()
			else sw.BackgroundColor3=Color3.fromRGB(55,55,60);knob.Position=UDim2.new(0,2,0,2)end
		end
	end
	ref();sw.MouseButton1Click:Connect(function()s(not g());ref(true)end);return{sw=sw,knob=knob,refresh=ref}
end
E.toggles={Learn=mkTg("学习模式",4,function()return STATE.LearningMode end,function(v)STATE.LearningMode=v end),Parry=mkTg("自动格挡",168,function()return STATE.AutoParry end,function(v)STATE.AutoParry=v end)}

local br=ui("Frame",{Size=UDim2.new(1,-12,0,28),Position=UDim2.new(0,6,0,36),BackgroundTransparency=1,Parent=sBg})
lbl("按键:",{Size=UDim2.new(0,36,0,20),Position=UDim2.new(0,2,0,3),TextXAlignment=Enum.TextXAlignment.Left,TextSize=11,TextColor3=Color3.fromRGB(155,158,165),Font=Enum.Font.GothamSemibold,Parent=br})
local keyBtn=ui("TextButton",{Text=STATE.KeyBindName,Size=UDim2.new(0,80,0,24),Position=UDim2.new(0,40,0,2),Font=Enum.Font.GothamSemibold,TextSize=11,BackgroundColor3=Color3.fromRGB(35,37,45),TextColor3=Color3.fromRGB(200,200,220),BorderSizePixel=1,BorderColor3=Color3.fromRGB(50,52,60),Parent=br});cr(12).Parent=keyBtn;E.keyBtn=keyBtn
local listening=false
keyBtn.MouseButton1Click:Connect(function()
	if listening then return end;listening=true;keyBtn.Text="按下...";keyBtn.BackgroundColor3=Color3.fromRGB(90,45,45)
	local conn;conn=UIS.InputBegan:Connect(function(inp,proc)if proc then return end;if inp.UserInputType==Enum.UserInputType.Keyboard then STATE.ParryKey=inp.KeyCode;STATE.KeyBindName=inp.KeyCode.Name;keyBtn.Text=STATE.KeyBindName;keyBtn.BackgroundColor3=Color3.fromRGB(55,55,68);listening=false;conn:Disconnect();saveSettings()end end)
	task.delay(6,function()if listening then listening=false;keyBtn.Text=(STATE.KeyBindName~="未设置")and STATE.KeyBindName or"超时";keyBtn.BackgroundColor3=Color3.fromRGB(55,55,68);conn:Disconnect()end end)
end)
local statusDot=ui("Frame",{Size=UDim2.new(0,6,0,6),Position=UDim2.new(0,132,0,10),BackgroundColor3=Color3.fromRGB(50,210,80),BorderSizePixel=0,Parent=br});ui("UICorner",{CornerRadius=UDim.new(0.5,0)}).Parent=statusDot
local statusInd=lbl("运行中",{Position=UDim2.new(0,142,0,2),Size=UDim2.new(0,120,0,20),TextXAlignment=Enum.TextXAlignment.Left,TextSize=10,TextColor3=Color3.fromRGB(140,210,150),Font=Enum.Font.GothamSemibold,Parent=br});E.statusInd=statusInd;E.statusDot=statusDot
coroutine.wrap(function()while true do task.wait(1.2)if statusDot and statusDot.Parent then TS:Create(statusDot,TweenInfo.new(0.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundTransparency=0.6}):Play();task.wait(0.6);TS:Create(statusDot,TweenInfo.new(0.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundTransparency=0}):Play()end end end)()
ui("Frame",{Size=UDim2.new(1,-12,0,1),Position=UDim2.new(0,6,0,82),BackgroundColor3=Color3.fromRGB(45,47,55),BorderSizePixel=0,Parent=body})

-- ====== 已学习列表 ======
lbl("时机%=动画播放到X%时格挡  ++大调 +=微调  -=-微减 --=-大减",{Size=UDim2.new(1,-12,0,18),Position=UDim2.new(0,6,0,88),TextXAlignment=Enum.TextXAlignment.Left,TextSize=10,TextColor3=Color3.fromRGB(120,125,135),Font=Enum.Font.GothamSemibold,Parent=body})
lbl("── 已学习 ──",{Size=UDim2.new(1,0,0,22),Position=UDim2.new(0,0,0,104),TextSize=12,TextColor3=Color3.fromRGB(150,150,170),Parent=body})
local tree=ui("ScrollingFrame",{Size=UDim2.new(1,0,0,310),Position=UDim2.new(0,0,0,130),BackgroundColor3=Color3.fromRGB(22,24,30),BorderSizePixel=1,BorderColor3=Color3.fromRGB(40,42,50),ScrollBarThickness=4,ScrollBarImageColor3=Color3.fromRGB(50,55,65),Parent=body,ZIndex=1});cr(10).Parent=tree;E.tree=tree

-- ====== 设置面板 ======
local settingsPanel=ui("Frame",{Size=UDim2.new(1,0,0,330),Position=UDim2.new(0,0,0,130),BackgroundColor3=Color3.fromRGB(22,24,30),BorderSizePixel=1,BorderColor3=Color3.fromRGB(40,42,50),Visible=false,Parent=body,ZIndex=10});cr(10).Parent=settingsPanel
cr(4).Parent=settingsPanel
lbl("设置",{Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,0,0,0),TextSize=14,TextColor3=Color3.fromRGB(215,215,235),Parent=settingsPanel})
local uvRow=ui("Frame",{Size=UDim2.new(1,-10,0,22),Position=UDim2.new(0,5,0,26),BackgroundTransparency=1,Parent=settingsPanel})
lbl("UI开关:",{Size=UDim2.new(0,50,0,20),Position=UDim2.new(0,2,0,1),TextSize=11,TextColor3=Color3.fromRGB(195,195,210),Parent=uvRow})
local uvBtn=ui("TextButton",{Text=STATE.UIVisKeyName,Size=UDim2.new(0,80,0,20),Position=UDim2.new(0,54,0,1),Font=Enum.Font.SourceSansBold,TextSize=12,BackgroundColor3=Color3.fromRGB(55,55,68),TextColor3=Color3.fromRGB(230,210,120),BorderSizePixel=0,Parent=uvRow,Active=true,AutoButtonColor=false});cr(3).Parent=uvBtn;E.uvBtn=uvBtn
local uvListening=false
uvBtn.MouseButton1Click:Connect(function()
	if uvListening then return end;uvListening=true;uvBtn.Text="按按键...";uvBtn.BackgroundColor3=Color3.fromRGB(90,45,45)
	local conn;conn=UIS.InputBegan:Connect(function(inp,proc)if proc then return end;if inp.UserInputType==Enum.UserInputType.Keyboard then STATE.UIVisToggleKey=inp.KeyCode;STATE.UIVisKeyName=inp.KeyCode.Name;uvBtn.Text=STATE.UIVisKeyName;uvBtn.BackgroundColor3=Color3.fromRGB(55,55,68);uvListening=false;conn:Disconnect();saveSettings()end end)
	task.delay(6,function()if uvListening then uvListening=false;uvBtn.Text=STATE.UIVisKeyName or"超时";uvBtn.BackgroundColor3=Color3.fromRGB(55,55,68);conn:Disconnect()end end)
end)
local rnRow=ui("Frame",{Size=UDim2.new(1,-10,0,20),Position=UDim2.new(0,5,0,50),BackgroundTransparency=1,Parent=settingsPanel})
lbl("范围:",{Size=UDim2.new(0,36,0,18),Position=UDim2.new(0,2,0,1),TextSize=10,TextColor3=Color3.fromRGB(195,195,210),Parent=rnRow})
local rnV=lbl(tostring(STATE.MaxRange),{Size=UDim2.new(0,24,0,18),Position=UDim2.new(0,38,0,1),TextSize=10,TextColor3=Color3.fromRGB(230,210,120),Parent=rnRow});E.rnV=rnV
local rnBg=ui("Frame",{Size=UDim2.new(0,120,0,5),Position=UDim2.new(0,64,0,7),BackgroundColor3=Color3.fromRGB(40,42,50),BorderSizePixel=0,Parent=rnRow});cr(2).Parent=rnBg
local rnFi=ui("Frame",{Size=UDim2.new(clamp(STATE.MaxRange/40,0,1),0,1,0),BackgroundColor3=Color3.fromRGB(100,160,230),BorderSizePixel=0,Parent=rnBg});cr(2).Parent=rnFi;E.rnFi=rnFi
local rnBn=ui("TextButton",{Text="",Size=UDim2.new(0,10,0,12),Position=UDim2.new(0,math.floor(59+clamp(STATE.MaxRange/40,0,1)*120),0,4),BackgroundColor3=Color3.fromRGB(200,200,220),BorderSizePixel=0,Parent=rnRow,Active=true,AutoButtonColor=false});cr(5).Parent=rnBn;E.rnBn=rnBn
local rConn;rnBn.MouseButton1Down:Connect(function()
	if rConn then rConn:Disconnect()end
	rConn=UIS.InputChanged:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseMovement then local r=clamp((UIS:GetMouseLocation().X-rnBg.AbsolutePosition.X)/rnBg.AbsoluteSize.X,0,1);STATE.MaxRange=math.floor(r*40+0.5);rnV.Text=tostring(STATE.MaxRange);rnFi.Size=UDim2.new(clamp(STATE.MaxRange/40,0,1),0,1,0);rnBn.Position=UDim2.new(0,math.floor(59+clamp(STATE.MaxRange/40,0,1)*120),0,4)end end)
	repeat local i=UIS.InputEnded:Wait()until i.UserInputType==Enum.UserInputType.MouseButton1
	if rConn then rConn:Disconnect();rConn=nil end;saveSettings()
end)
local fcRow=ui("Frame",{Size=UDim2.new(1,-10,0,22),Position=UDim2.new(0,5,0,72),BackgroundTransparency=1,Parent=settingsPanel})
lbl("面朝检测:",{Size=UDim2.new(0,60,0,20),Position=UDim2.new(0,2,0,1),TextSize=11,TextColor3=Color3.fromRGB(195,195,210),Parent=fcRow})
local fcBtn=ui("TextButton",{Text=STATE.FacingCheck and"开启"or"关闭",Size=UDim2.new(0,34,0,20),Position=UDim2.new(0,64,0,1),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=STATE.FacingCheck and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70),TextColor3=STATE.FacingCheck and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210),BorderSizePixel=0,Parent=fcRow,Active=true,AutoButtonColor=false});cr(3).Parent=fcBtn
fcBtn.MouseButton1Click:Connect(function()STATE.FacingCheck=not STATE.FacingCheck;fcBtn.Text=STATE.FacingCheck and"开启"or"关闭";fcBtn.BackgroundColor3=STATE.FacingCheck and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70);fcBtn.TextColor3=STATE.FacingCheck and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210);saveSettings()end)
E.fcBtn=fcBtn
local atRow=ui("Frame",{Size=UDim2.new(1,-10,0,22),Position=UDim2.new(0,5,0,96),BackgroundTransparency=1,Parent=settingsPanel})
lbl("自动时机:",{Size=UDim2.new(0,60,0,20),Position=UDim2.new(0,2,0,1),TextSize=11,TextColor3=Color3.fromRGB(195,195,210),Parent=atRow})
local atBtn=ui("TextButton",{Text=STATE.AutoTiming and"开启"or"关闭",Size=UDim2.new(0,34,0,20),Position=UDim2.new(0,64,0,1),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=STATE.AutoTiming and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70),TextColor3=STATE.AutoTiming and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210),BorderSizePixel=0,Parent=atRow,Active=true,AutoButtonColor=false});cr(3).Parent=atBtn
atBtn.MouseButton1Click:Connect(function()STATE.AutoTiming=not STATE.AutoTiming;atBtn.Text=STATE.AutoTiming and"开启"or"关闭";atBtn.BackgroundColor3=STATE.AutoTiming and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70);atBtn.TextColor3=STATE.AutoTiming and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210);saveSettings()end)
E.atBtn=atBtn
local fzRow=ui("Frame",{Size=UDim2.new(1,-10,0,22),Position=UDim2.new(0,5,0,120),BackgroundTransparency=1,Parent=settingsPanel})
lbl("冻结已学:",{Size=UDim2.new(0,60,0,20),Position=UDim2.new(0,2,0,1),TextSize=11,TextColor3=Color3.fromRGB(195,195,210),Parent=fzRow})
local fzBtn=ui("TextButton",{Text=STATE.FreezeOnLearn and"开启"or"关闭",Size=UDim2.new(0,34,0,20),Position=UDim2.new(0,64,0,1),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=STATE.FreezeOnLearn and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70),TextColor3=STATE.FreezeOnLearn and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210),BorderSizePixel=0,Parent=fzRow,Active=true,AutoButtonColor=false});cr(3).Parent=fzRow
fzBtn.MouseButton1Click:Connect(function()STATE.FreezeOnLearn=not STATE.FreezeOnLearn;fzBtn.Text=STATE.FreezeOnLearn and"开启"or"关闭";fzBtn.BackgroundColor3=STATE.FreezeOnLearn and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70);fzBtn.TextColor3=STATE.FreezeOnLearn and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210);saveSettings()end)
E.fzBtn=fzBtn
local kwY=144
lbl("── 过滤关键词 ──",{Size=UDim2.new(1,0,0,18),Position=UDim2.new(0,0,0,kwY),TextSize=11,TextColor3=Color3.fromRGB(150,150,170),Parent=settingsPanel})
local kwBox=ui("ScrollingFrame",{Size=UDim2.new(1,-8,0,130),Position=UDim2.new(0,4,0,kwY+18),BackgroundColor3=Color3.fromRGB(10,12,18),BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=Color3.fromRGB(50,55,65),CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,Parent=settingsPanel,ZIndex=11});cr(6).Parent=kwBox
local function refreshKW()
	kwBox:ClearAllChildren();ui("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,1),Parent=kwBox})
	for i,kw in ipairs(blockedPrefixes)do
		local kwRow=ui("Frame",{Size=UDim2.new(1,0,0,18),BackgroundTransparency=1,Parent=kwBox})
		lbl(kw,{Size=UDim2.new(1,-24,0,16),Position=UDim2.new(0,2,0,1),TextXAlignment=Enum.TextXAlignment.Left,TextSize=10,TextColor3=Color3.fromRGB(190,195,210),Parent=kwRow})
		local delKw=ui("TextButton",{Text="✕",Size=UDim2.new(0,16,0,16),Position=UDim2.new(1,-18,0,1),Font=Enum.Font.SourceSansBold,TextSize=10,BackgroundColor3=Color3.fromRGB(55,30,30),TextColor3=Color3.fromRGB(200,90,90),BorderSizePixel=0,Parent=kwRow,Active=true,AutoButtonColor=false});cr(2).Parent=delKw
		delKw.MouseButton1Click:Connect(function()table.remove(blockedPrefixes,i);refreshKW()end)
	end
end
refreshKW()
local addRow=ui("Frame",{Size=UDim2.new(1,-8,0,22),Position=UDim2.new(0,4,0,kwY+150),BackgroundTransparency=1,Parent=settingsPanel})
local addBox=ui("TextBox",{Text="",PlaceholderText="输入关键词...",Size=UDim2.new(0,100,0,20),Position=UDim2.new(0,0,0,1),Font=Enum.Font.SourceSans,TextSize=12,TextColor3=Color3.fromRGB(225,225,235),PlaceholderColor3=Color3.fromRGB(100,105,120),BackgroundColor3=Color3.fromRGB(14,16,24),BorderSizePixel=0,ClearTextOnFocus=false,Parent=addRow});cr(4).Parent=addBox
local addKwBtn=ui("TextButton",{Text="+添加",Size=UDim2.new(0,52,0,20),Position=UDim2.new(0,104,0,1),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=Color3.fromRGB(50,80,50),TextColor3=Color3.fromRGB(160,230,160),BorderSizePixel=0,Parent=addRow,Active=true,AutoButtonColor=false});cr(3).Parent=addKwBtn
addKwBtn.MouseButton1Click:Connect(function()
	local t=addBox.Text:lower():match("^%s*(.-)%s*$")or""
	if t~=""then
		local found=false;for _,k in ipairs(blockedPrefixes)do if k==t then found=true;break end end
		if not found then table.insert(blockedPrefixes,t);refreshKW();saveKW()end
		addBox.Text=""
	end
end)

-- ====== 加载面板 ======
local loadPanel=ui("Frame",{Size=UDim2.new(1,0,0,240),Position=UDim2.new(0,0,0,0),BackgroundColor3=Color3.fromRGB(22,24,30),BorderSizePixel=1,BorderColor3=Color3.fromRGB(40,42,50),Visible=false,Parent=body,ZIndex=10});cr(10).Parent=loadPanel
cr(4).Parent=loadPanel
lbl("加载数据",{Size=UDim2.new(1,0,0,24),TextSize=14,TextColor3=Color3.fromRGB(215,215,235),Parent=loadPanel})
local loadBox=ui("ScrollingFrame",{Size=UDim2.new(1,-8,1,-28),Position=UDim2.new(0,4,0,24),BackgroundColor3=Color3.fromRGB(10,12,18),BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=Color3.fromRGB(50,55,65),CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,Parent=loadPanel,ZIndex=11});cr(6).Parent=loadBox
local function refreshLoadPanel()
	loadBox:ClearAllChildren();ui("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,2),Parent=loadBox})
	local curFr=ui("Frame",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Parent=loadBox})
	lbl("当前游戏: "..tostring(game.GameId or game.Name or"0"),{Size=UDim2.new(1,-52,0,22),Position=UDim2.new(0,2,0,1),TextXAlignment=Enum.TextXAlignment.Left,TextSize=11,TextColor3=Color3.fromRGB(215,215,220),Parent=curFr})
	local curLb=ui("TextButton",{Text="加载",Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-48,0,1),Font=Enum.Font.GothamSemibold,TextSize=10,BackgroundColor3=Color3.fromRGB(50,90,60),TextColor3=Color3.fromRGB(160,230,170),BorderSizePixel=0,Parent=curFr,Active=true,AutoButtonColor=false});cr(11).Parent=curLb
	curLb.MouseButton1Click:Connect(function()table.clear(learnedAnims);table.clear(folderExpanded);table.clear(animExpanded);loadAll();loadKW();if E.BuildTree then E:BuildTree()end;loadPanel.Visible=false end)
	local allDirs=listfiles(rootDir.."/")
	for _,d in ipairs(allDirs)do
		if d:match(gameDir)then break end
		local gid=d:match(rootDir.."/(.+)")
		if gid and gid~=""then
			local hasFile=pcall(readfile,d.."/Data.json")
			if hasFile then
				lbl("── "..gid.." ──",{Size=UDim2.new(1,0,0,20),TextSize=11,TextColor3=Color3.fromRGB(150,150,170),Parent=loadBox})
				local fr=ui("Frame",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Parent=loadBox})
				lbl(gid,{Size=UDim2.new(1,-52,0,22),Position=UDim2.new(0,2,0,1),TextXAlignment=Enum.TextXAlignment.Left,TextSize=11,TextColor3=Color3.fromRGB(195,200,210),Parent=fr})
				local lb=ui("TextButton",{Text="加载",Size=UDim2.new(0,44,0,22),Position=UDim2.new(1,-48,0,1),Font=Enum.Font.GothamSemibold,TextSize=10,BackgroundColor3=Color3.fromRGB(50,90,60),TextColor3=Color3.fromRGB(160,230,170),BorderSizePixel=0,Parent=fr,Active=true,AutoButtonColor=false});cr(11).Parent=lb
				lb.MouseButton1Click:Connect(function()table.clear(learnedAnims);table.clear(folderExpanded);table.clear(animExpanded);local ok,rw=pcall(readfile,d.."/Data.json");if ok and rw and rw~=""then local od=HttpService:JSONDecode(rw);if od then for s,src in pairs(od)do for aid,a in pairs(src.anims)do learnedAnims[aid]={name=a.n,sourceName=s,sourceType=src.type or"NPC",seenCount=a.sc or 0,parryCount=a.pc or 0,attackHits=a.ah or 0,timings=a.tn or{},avgTiming=a.av or 0.5,hold=a.ho or 0.08,enabled=a.en,locked=a.lo,timingLocked=a.tl,length=a.le or 1}end end end end;loadKW();if E.BuildTree then E:BuildTree()end;loadPanel.Visible=false end)
			end
		end
	end
end

local foot=ui("Frame",{Size=UDim2.new(1,0,0,36),Position=UDim2.new(0,0,0,444),BackgroundTransparency=1,ZIndex=20,Parent=body})
local function mkBtn(t,x,cb)local b=ui("TextButton",{Text=t,Size=UDim2.new(0,52,0,26),Position=UDim2.new(0,x,0,5),Font=Enum.Font.GothamSemibold,TextSize=10,BackgroundColor3=Color3.fromRGB(40,42,50),TextColor3=Color3.fromRGB(210,210,220),BorderSizePixel=0,Parent=foot});cr(13).Parent=b;if cb then b.MouseButton1Click:Connect(cb)end;return b end
mkBtn("重置",4,function()table.clear(learnedAnims);table.clear(recentAnims);table.clear(activeAnims);table.clear(folderExpanded);table.clear(animExpanded);if E.BuildTree then E:BuildTree()end end)
mkBtn("加载",60,function()loadPanel.Visible=not loadPanel.Visible;loadPanel.ZIndex=loadPanel.Visible and 12 or 10;refreshLoadPanel()end)
mkBtn("保存",116,function()saveAll()end)
local pauseBtn=mkBtn("⏸",172)
pauseBtn.MouseButton1Click:Connect(function()STATE.Active=not STATE.Active;if STATE.Active then pauseBtn.Text="⏸";pauseBtn.BackgroundColor3=Color3.fromRGB(65,60,45);statusInd.Text="运行中";statusInd.TextColor3=Color3.fromRGB(140,210,150);if E.statusDot then E.statusDot.BackgroundColor3=Color3.fromRGB(50,210,80)end else pauseBtn.Text="▶";pauseBtn.BackgroundColor3=Color3.fromRGB(45,45,55);statusInd.Text="已暂停";statusInd.TextColor3=Color3.fromRGB(170,170,180);if E.statusDot then E.statusDot.BackgroundColor3=Color3.fromRGB(180,180,180)end end end)
local setBtn=mkBtn("⚙",228)
setBtn.MouseButton1Click:Connect(function()settingsPanel.Visible=not settingsPanel.Visible end)
E.sg=sg;E.win=win
UIS.InputBegan:Connect(function(input,processed)if STATE.UIVisToggleKey and input.KeyCode==STATE.UIVisToggleKey and win then win.Visible=not win.Visible end;if processed then return end;if STATE.ParryKey and input.KeyCode==STATE.ParryKey then onPlayerParry()end end)

-- ====== BuildTree（修复 shortId bug） ======
function E:BuildTree()
	tree:ClearAllChildren();ui("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,2),Parent=tree})
	local sources={}
	for aid,a in pairs(learnedAnims)do
		if not isConfirmed(a)then continue end
		local sn=a.sourceName or"未知"
		if not sources[sn]then sources[sn]={type=a.sourceType or"NPC",anims={}}end
		sources[sn].anims[aid]=a
	end
	local snames={};for n in pairs(sources)do snames[#snames+1]=n end;table.sort(snames)
	local updateTreeCanvasPending=false
	local function updateTreeCanvas()
		if updateTreeCanvasPending then return end
		updateTreeCanvasPending=true
		task.spawn(function()
			task.wait()
			updateTreeCanvasPending=false
			local layout=tree:FindFirstChildOfClass("UIListLayout")
			if layout then tree.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y)end
		end)
	end
	for _,sn in ipairs(snames)do
		local src=sources[sn];local count=0;for _ in pairs(src.anims)do count+=1 end
		local ic=src.type=="Player"and"👤"or"🤖"
		local fRow=ui("Frame",{Size=UDim2.new(1,-6,0,24),BackgroundTransparency=1,Parent=tree})
		local fBtn=ui("TextButton",{Text=string.format("▶ %s %s(%d)",ic,sn,count),Size=UDim2.new(1,-84,0,22),Position=UDim2.new(0,2,0,1),TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.SourceSansBold,TextSize=13,TextColor3=Color3.fromRGB(200,210,220),BackgroundColor3=Color3.fromRGB(32,34,42),BorderSizePixel=0,Parent=fRow,Active=true,AutoButtonColor=false});cr(4).Parent=fBtn
		local fe=folderExpanded[sn]or false
		fBtn.Text=string.format("%s %s %s(%d)",fe and"▼"or"▶",ic,sn,count)
		fBtn.BackgroundColor3=fe and Color3.fromRGB(40,42,52)or Color3.fromRGB(32,34,42)
		local lkSrc=ui("TextButton",{Text=lockedSources[sn]and"🔒"or"🔓",Size=UDim2.new(0,22,0,20),Position=UDim2.new(1,-80,0,2),Font=Enum.Font.SourceSansBold,TextSize=12,BackgroundColor3=lockedSources[sn]and Color3.fromRGB(60,45,30)or Color3.fromRGB(45,45,55),TextColor3=lockedSources[sn]and Color3.fromRGB(230,200,120)or Color3.fromRGB(180,180,200),BorderSizePixel=0,Parent=fRow,Active=true,AutoButtonColor=false});cr(4).Parent=lkSrc
		lkSrc.MouseButton1Click:Connect(function()lockedSources[sn]=not lockedSources[sn];lkSrc.Text=lockedSources[sn]and"🔒"or"🔓";lkSrc.BackgroundColor3=lockedSources[sn]and Color3.fromRGB(60,45,30)or Color3.fromRGB(45,45,55);lkSrc.TextColor3=lockedSources[sn]and Color3.fromRGB(230,200,120)or Color3.fromRGB(180,180,200);saveSettings()end)
		local svSrc=ui("TextButton",{Text="💾",Size=UDim2.new(0,22,0,20),Position=UDim2.new(1,-54,0,2),Font=Enum.Font.SourceSansBold,TextSize=12,BackgroundColor3=Color3.fromRGB(40,60,45),TextColor3=Color3.fromRGB(150,220,160),BorderSizePixel=0,Parent=fRow,Active=true,AutoButtonColor=false});cr(4).Parent=svSrc
		svSrc.MouseButton1Click:Connect(function()saveSource(sn);saveKW()end)
		local delSrc=ui("TextButton",{Text="✕",Size=UDim2.new(0,22,0,20),Position=UDim2.new(1,-28,0,2),Font=Enum.Font.SourceSansBold,TextSize=14,BackgroundColor3=Color3.fromRGB(60,35,35),TextColor3=Color3.fromRGB(200,100,100),BorderSizePixel=0,Parent=fRow,Active=true,AutoButtonColor=false});cr(4).Parent=delSrc
		delSrc.MouseButton1Click:Connect(function()for aid,_ in pairs(src.anims)do learnedAnims[aid]=nil end;delSource(sn);E:BuildTree()end)
		local subF=ui("Frame",{BackgroundTransparency=1,ClipsDescendants=true,Parent=tree})
		ui("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,2),Parent=subF})
		local aids={};for aid in pairs(src.anims)do aids[#aids+1]=aid end;table.sort(aids)
		for _,aid in ipairs(aids)do
			local a=src.anims[aid]
			local an=(a.name and #a.name>0)and a.name or("a_"..aid:sub(-8))
			local tp=math.floor(clamp((a.avgTiming or 0)*100,0,100))
			local box=ui("Frame",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,Parent=subF})
			local aRow=ui("Frame",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,Parent=box})
			lbl("🎬 "..an,{Size=UDim2.new(0,140,0,20),Position=UDim2.new(0,4,0,1),TextXAlignment=Enum.TextXAlignment.Left,TextSize=12,TextColor3=Color3.fromRGB(215,215,220),Parent=aRow})
			local mainPct=lbl(tostring(tp).."%",{Size=UDim2.new(0,30,0,20),Position=UDim2.new(0,148,0,1),TextSize=11,TextColor3=Color3.fromRGB(140,190,230),Parent=aRow})
			local eb=ui("TextButton",{Text=a.enabled and"✓"or"✗",Size=UDim2.new(0,22,0,18),Position=UDim2.new(0,180,0,2),Font=Enum.Font.SourceSansBold,TextSize=13,BackgroundColor3=a.enabled and Color3.fromRGB(50,100,60)or Color3.fromRGB(65,50,50),TextColor3=a.enabled and Color3.fromRGB(180,255,180)or Color3.fromRGB(190,160,160),BorderSizePixel=0,Parent=aRow,Active=true,AutoButtonColor=false});cr(4).Parent=eb
			eb.MouseButton1Click:Connect(function()a.enabled=not a.enabled;eb.Text=a.enabled and"✓"or"✗";eb.BackgroundColor3=a.enabled and Color3.fromRGB(50,100,60)or Color3.fromRGB(65,50,50);eb.TextColor3=a.enabled and Color3.fromRGB(180,255,180)or Color3.fromRGB(190,160,160)end)
			local pe=animExpanded[aid]or false;local pSub=nil
			local pBtn=ui("TextButton",{Text=pe and"▼"or"▶",Size=UDim2.new(0,20,0,18),Position=UDim2.new(0,204,0,2),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=Color3.fromRGB(45,45,55),TextColor3=Color3.fromRGB(180,180,200),BorderSizePixel=0,Parent=aRow,Active=true,AutoButtonColor=false});cr(3).Parent=pBtn
			pBtn.MouseButton1Click:Connect(function()
				pe=not pe;animExpanded[aid]=pe;pBtn.Text=pe and"▼"or"▶"
				if pSub then pSub.Visible=pe end
				box.Size=UDim2.new(1,0,0,pe and 62 or 22)
				subF.Size=UDim2.new(1,-12,0,subF.Size.Y.Offset+(pe and 40 or -40))
				updateTreeCanvas()
			end)
			local delAnim=ui("TextButton",{Text="✕",Size=UDim2.new(0,18,0,18),Position=UDim2.new(0,226,0,2),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=Color3.fromRGB(55,30,30),TextColor3=Color3.fromRGB(200,90,90),BorderSizePixel=0,Parent=aRow,Active=true,AutoButtonColor=false});cr(3).Parent=delAnim
			delAnim.MouseButton1Click:Connect(function()learnedAnims[aid]=nil;saveSource(sn);E:BuildTree()end)
			-- 参数面板（折叠用 Visible 控制，自动布局）
			pSub=ui("Frame",{Size=UDim2.new(1,-6,0,40),Position=UDim2.new(0,3,0,24),BackgroundTransparency=1,Visible=pe,Parent=box})
			local tr=ui("Frame",{Size=UDim2.new(1,0,0,20),Position=UDim2.new(0,0,0,0),BackgroundTransparency=1,Parent=pSub})
			local tl=lbl(string.format("时机:%d%%",math.floor((a.avgTiming or 0.5)*100)),{Size=UDim2.new(0,70,0,18),Position=UDim2.new(0,0,0,1),TextSize=11,TextColor3=Color3.fromRGB(160,200,230),TextXAlignment=Enum.TextXAlignment.Left,Parent=tr})
			local tlk=ui("TextButton",{Text=a.timingLocked and"🔒"or"🔓",Size=UDim2.new(0,18,0,16),Position=UDim2.new(0,72,0,2),Font=Enum.Font.SourceSansBold,TextSize=10,BackgroundColor3=Color3.fromRGB(40,40,50),TextColor3=Color3.fromRGB(180,180,190),BorderSizePixel=0,Parent=tr,Active=true,AutoButtonColor=false});cr(3).Parent=tlk
			tlk.MouseButton1Click:Connect(function()a.timingLocked=not a.timingLocked;tlk.Text=a.timingLocked and"🔒"or"🔓"end)
			local function ta(x,d,t)local b=ui("TextButton",{Text=t or(d>0 and"+"or"-"),Size=UDim2.new(0,20,0,16),Position=UDim2.new(0,x,0,2),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=Color3.fromRGB(50,50,60),TextColor3=Color3.fromRGB(200,200,210),BorderSizePixel=0,Parent=tr,Active=true,AutoButtonColor=false});cr(3).Parent=b;b.MouseButton1Click:Connect(function()a.avgTiming=clamp((a.avgTiming or 0.5)+d,0.05,1.0);local pct=math.floor(a.avgTiming*100);tl.Text=string.format("时机:%d%%",pct);mainPct.Text=tostring(pct).."%"end)end
			ta(94,0.05,"++");ta(116,0.01,"+");ta(138,-0.01,"-");ta(160,-0.05,"--")
			local hr=ui("Frame",{Size=UDim2.new(1,0,0,20),Position=UDim2.new(0,0,0,20),BackgroundTransparency=1,Parent=pSub})
			local hl=lbl(string.format("按住:%dms",math.floor((a.hold or 0.08)*1000)),{Size=UDim2.new(0,70,0,18),Position=UDim2.new(0,0,0,1),TextSize=11,TextColor3=Color3.fromRGB(230,200,160),TextXAlignment=Enum.TextXAlignment.Left,Parent=hr})
			local function ha(x,d,t)local b=ui("TextButton",{Text=t or(d>0 and"+"or"-"),Size=UDim2.new(0,20,0,16),Position=UDim2.new(0,x,0,2),Font=Enum.Font.SourceSansBold,TextSize=11,BackgroundColor3=Color3.fromRGB(50,50,60),TextColor3=Color3.fromRGB(200,200,210),BorderSizePixel=0,Parent=hr,Active=true,AutoButtonColor=false});cr(3).Parent=b;b.MouseButton1Click:Connect(function()a.hold=clamp((a.hold or 0.08)+d,0.02,0.5);hl.Text=string.format("按住:%dms",math.floor(a.hold*1000))end)end
			ha(94,0.05,"++");ha(116,0.01,"+");ha(138,-0.01,"-");ha(160,-0.05,"--")
		end
		local function calcSubH()
			local ae=0;for _,aid in ipairs(aids)do if animExpanded[aid]then ae+=1 end end
			return #aids*22+ae*40+(#aids-1)*2
		end
		subF.Size=UDim2.new(1,-12,0,fe and calcSubH()or 0)
		fBtn.MouseButton1Click:Connect(function()
			fe=not fe;folderExpanded[sn]=fe;fBtn.Text=string.format("%s %s %s(%d)",fe and"▼"or"▶",ic,sn,count)
			fBtn.BackgroundColor3=fe and Color3.fromRGB(40,42,52)or Color3.fromRGB(32,34,42)
			subF.Size=UDim2.new(1,-12,0,fe and calcSubH()or 0)
			updateTreeCanvas()
		end)
	end
	updateTreeCanvas()
end;E:BuildTree()

-- ====== Ping 采集 ======
coroutine.wrap(function()
	while true do
		task.wait(1)
		local ok,v=pcall(function()
			local s=game:GetService("Stats")
			local a=s and s:FindFirstChild("Network")
			if a then
				local b=a:FindFirstChild("ServerStatsItem")
				if b then
					local c=b:FindFirstChild("Data Ping")
					if c then return c:GetValue()end
				end
			end
			local d=s and s:FindFirstChild("PerformanceStats")
			if d then
				local e=d:FindFirstChild("DataInts")
				if e then
					local f=e:FindFirstChild("Ping")
					if f then return f:GetValue()end
				end
			end
			return 0
		end)
		local p=ok and v or 0
		table.insert(pingSamples,p);while #pingSamples>5 do table.remove(pingSamples,1)end
		local sum=0;for _,s in ipairs(pingSamples)do sum+=s end;currentPing=#pingSamples>0 and sum/#pingSamples or 0
	end
end)()

-- ====== 启动 ======
local ok,err=pcall(function()trackAll();task.wait(0.5);scanExistingNPCs();loadSettings();loadAll();saveKW();saveSettings();if E.BuildTree then E:BuildTree()end;if E.keyBtn then E.keyBtn.Text=STATE.KeyBindName end;if E.uvBtn then E.uvBtn.Text=STATE.UIVisKeyName end;if E.fcBtn then E.fcBtn.Text=STATE.FacingCheck and"开启"or"关闭";E.fcBtn.BackgroundColor3=STATE.FacingCheck and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70);E.fcBtn.TextColor3=STATE.FacingCheck and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210)end;if E.fzBtn then E.fzBtn.Text=STATE.FreezeOnLearn and"开启"or"关闭";E.fzBtn.BackgroundColor3=STATE.FreezeOnLearn and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70);E.fzBtn.TextColor3=STATE.FreezeOnLearn and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210)end;if E.atBtn then E.atBtn.Text=STATE.AutoTiming and"开启"or"关闭";E.atBtn.BackgroundColor3=STATE.AutoTiming and Color3.fromRGB(50,100,60)or Color3.fromRGB(60,60,70);E.atBtn.TextColor3=STATE.AutoTiming and Color3.fromRGB(160,240,170)or Color3.fromRGB(200,200,210)end;if E.rnV then E.rnV.Text=tostring(STATE.MaxRange);E.rnFi.Size=UDim2.new(clamp(STATE.MaxRange/40,0,1),0,1,0);E.rnBn.Position=UDim2.new(0,math.floor(59+clamp(STATE.MaxRange/40,0,1)*120),0,4)end;sg.AncestryChanged:Connect(function()if sg and not sg.Parent then local p=getSP();if p then sg.Parent=p end end end);coroutine.wrap(function()while true do task.wait(5);if sg and not sg.Parent then local p=getSP();if p then sg.Parent=p end end end end)()end)
if not ok then warn("[AP]启动失败:",err)end