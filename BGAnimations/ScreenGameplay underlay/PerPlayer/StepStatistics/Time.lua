local player = ...
local PlayerState  = GAMESTATE:GetPlayerState(player)
local SongPosition = GAMESTATE:GetPlayerState(player):GetSongPosition()
local rate = SL.Global.ActiveModifiers.MusicRate
local pn = ToEnumShortString(player)
local pnum = tonumber(player:sub(-1))
local mods = SL[pn].ActiveModifiers
local useitg = mods.SimulateITGEnv

if (mods.TimeElapsed == false) then return end

local curBMT -- elapsed time
local remBMT -- remaining time
local alive = true -- will continue updating as long as player is alive

-- Format to HH:MM:SS
local hours, mins, secs
local hmmss = "%d:%02d:%02d"

local SecondsToHMMSS = SecondsToHMMSS or function(s)
	hours = math.floor(s/3600)
	mins  = math.floor((s % 3600) / 60)
	secs  = s - (hours * 3600) - (mins * 60)
	return hmmss:format(hours, mins, secs)
end

local fmt = nil

-- how long this song or course is, in seconds
local totalseconds = 0

if GAMESTATE:IsCourseMode() then
	local trail = GAMESTATE:GetCurrentTrail(player)
	if trail then totalseconds = TrailUtil.GetTotalSeconds(trail) end
else
	local song = GAMESTATE:GetCurrentSong()
	if song then totalseconds = song:GetLastSecond() end
end

totalseconds = totalseconds / rate -- factor in MusicRate

-- choose the appropriate time-to-string formatting function
local length

-- shorter than 10 minutes (M:SS)
if totalseconds < 600 then fmt = SecondsToMSS
-- at least 10 minutes, shorter than 1 hour (MM:SS)
elseif totalseconds >= 360 and totalseconds < 3600 then fmt = SecondsToMMSS
-- somewhere between 1 and 10 hours (H:MM:SS)
elseif totalseconds >= 3600 and totalseconds < 36000 then fmt = SecondsToHMMSS
-- 10 hours or longer (HH:MM:SS)
else fmt = SecondsToHHMMSS
end

local totalwidth -- Use this to find out the width of the remaining time  to make it look nice
-- -----------------------------------------------------------------------
-- In CourseMode, we want to show how far into the overall Course the player is,
-- but SongPosition:GetMusicSeconds() only gives us the current second into the current
-- song.  We'll need to track how long each song is, and add (cumulatively-increasing)
-- seconds to SongPosition:GetMusicSeconds() for each song past the first.
--
-- Here, set up a table with cumulative seconds-per-Song for the overall Course.
local cumulative_seconds = {}

if GAMESTATE:IsCourseMode() then
	local seconds = 0
	local trail = GAMESTATE:GetCurrentTrail(player)

	if trail then
		local entries = trail:GetTrailEntries()
		for i, entry in ipairs(entries) do
			-- In the engine, TrailUtil.GetTotalSeconds() adds up song.MusicLengthSeconds
			-- so let's use the same method here for consistency.
			seconds = seconds + (entry:GetSong():MusicLengthSeconds() / rate)
			table.insert(cumulative_seconds, seconds)
		end
	end
end

-- variable scoped to this entire file, updated in CurrentSongChangedMessageCommand
-- so it can be included in calculatations in Update()
local seconds_offset = 0

-- -----------------------------------------------------------------------
-- this Update function will be called every frame (I think)
-- it's potentially dangerous for framerate

local Update = function(af, delta)
	if not alive then return end

	-- SongPosition:GetMusicSeconds() can be negative for a bit at
	-- the beginnging depending on how the stepartist set the offset
	-- don't show negative time; just use 0
	if SongPosition:GetMusicSeconds() < 0 then
		curBMT:settext(fmt(seconds_offset))
		remBMT:settext(fmt(totalseconds - seconds_offset))
		return
	end

	curBMT:settext( fmt((SongPosition:GetMusicSeconds() / rate) +  seconds_offset) )
	remBMT:settext( fmt(clamp(totalseconds - seconds_offset - (SongPosition:GetMusicSeconds()/rate), 0, totalseconds)) )
	
end

-- -----------------------------------------------------------------------
local c = PREFSMAN:GetPreference("Center1Player")
local ar = GetScreenAspectRatio()

local x = _screen.cx/2 -- Align to the middle of the screen ish
local xoffset = -1
local yoffset = 0
local y = 8
local zoom = 0.75

if c then -- Center 1 player has off center step stats
	if ar > 1.7 then 
		-- 16:9
		xoffset = -47 
		yoffset = -4
		zoom = 0.9
	else 
		--16:10
		xoffset = -37 
		zoom = 0.95
	end
end

local row_height = 15 

local songlabel = GAMESTATE:IsCourseMode() and THEME:GetString("ScreenGameplay", "Course") or "Song"

local labels = { 'Elapsed', 'Remain', songlabel }

local af = Def.ActorFrame {
	Name="TimeAF",
	-- Initial Setup positioning
	InitCommand=function(self)
		self:SetUpdateFunction(Update)
	end,
	OnCommand=function(self)
		self:xy((x+xoffset)*(pnum*2-3) ,y+yoffset)	
		self:zoom(zoom)
	end
}

-- Time Elapsed
af[#af+1] = LoadFont("Common Normal")..{
	InitCommand=function(self)
		curBMT = self
		--self:x(0)
		self:y(row_height*1)
		self:horizalign((pnum == 1) and left or right)
	end,
	[(useitg and "ITG" or "WF") .. "FailedMessageCommand"]=function(self, params)
		self:diffuse(color("#ff3030"))
		alive = false
	end
}

---- Time Remaining
af[#af+1] = LoadFont("Common Normal")..{
	InitCommand=function(self)
		remBMT = self
		self:y(row_height*2)
		self:horizalign((pnum == 1) and left or right)
	end,
	[(useitg and "ITG" or "WF") .. "FailedMessageCommand"]=function(self, params)
		self:diffuse(color("#ff3030"))
		alive = false
	end
}

---- Total time
af[#af+1] = LoadFont("Common Normal")..{
	InitCommand=function(self)
		self:settext(fmt(totalseconds))
		self:y(row_height*3)
		self:horizalign((pnum == 1) and left or right)
		totalwidth = -self:GetWidth() - 5
	end,
}

-- Labels
for i, label in ipairs(labels) do		
	af[#af+1] = LoadFont("Common Normal")..{
		InitCommand=function(self)
			self:x(totalwidth*(pnum*2-3)) -- put the label close to the number
			self:y(row_height*i)
			self:settext(label)
			self:horizalign((pnum == 1) and left or right) -- invert so the value is easier to see while playing
		end,
	}
end


af.CurrentSongChangedMessageCommand=function(self,params)
	-- GAMESTATE:GetCourseSongIndex() is 0-indexed, which we'll use to our advantage here
	-- since CurrentSongChanged is broadcast by the engine at the start of every song in
	-- a course, including the first.
	--
	-- So, when ScreenGameplay appears for the first song in the course, GAMESTATE:GetCourseSongIndex()
	-- will be 0, which won't index to anything in cumulative_seconds, which is what we want.
	--
	-- When the 2nd song appears, GAMESTATE:GetCourseSongIndex() will be 1, meaning we'll index
	-- cumulative_seconds[1] to get the first song's duration.
	--
	-- When the 3rd song appears, we'll index cumulative_seconds[2] to get (1st song + 2nd song)
	-- duration.  Etc.
	local course_index = GAMESTATE:GetCourseSongIndex()
	seconds_offset = cumulative_seconds[course_index] or 0
end

return af