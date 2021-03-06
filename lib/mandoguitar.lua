-- local json=include("mandoguitar/lib/json")
local lattice=require("lattice")
local MusicUtil = require "musicutil"
local mxsamples=include("mx.samples/lib/mx.samples")


engine.name="MxSamples"

local mx=mxsamples:new()
local Mandoguitar={}

function Mandoguitar:new(args)
  local m=setmetatable({},{__index=Mandoguitar})
  local args=args==nil and {} or args
  m.grid_on=args.grid_on==nil and true or args.grid_on
  m.toggleable=args.toggleable==nil and false or args.toggleable

  m.scene="a"

  -- initiate the grid
  m.g=grid.connect()
  m.grid64=m.g.cols==8
  m.grid64default=true
  m.grid_width=16
  m.g.key=function(x,y,z)
    if m.grid_on then
      m:grid_key(x,y,z)
    end
  end
  print("grid columns: "..m.g.cols)

  -- allow toggling
  m.kill_timer=0

  -- setup visual
  m.visual={}
  for i=1,8 do
    m.visual[i]={}
    for j=1,m.grid_width do
      m.visual[i][j]=0
    end
  end

  -- debouncing and blinking
  m.blink_count=0
  m.blinky={}
  for i=1,m.grid_width do
    m.blinky[i]=1 -- 1 = fast, 16 = slow
  end

  -- keep track of pressed buttons
  m.pressed_buttons={}

  -- define num voices
  m.num_voices=2

  -- setup step sequencer
  m.voices={}
  for i=1,m.num_voices do
    m.voices[i]={
      division=8,-- 8 = quartner notes
      is_playing=false,
      is_recording=false,
      in_menu=false,
      steps={},
      step=0,
      step_val=0,
      pitch_mod_i=5,
    }
  end

  -- setup lattice
  -- lattice
  -- for keeping time of all the divisions
  m.lattice=lattice:new({
    ppqn=48
  })
  m.timers={}
  local divisions = {1,2,4,6,8,12,16}
  for _,division in ipairs(divisions) do
    m.timers[division]={}
    m.timers[division].lattice=m.lattice:new_pattern{
      action=function(t)
        m:emit_note(division)
      end,
    division=1/(division/2)}
  end
  m.lattice:start()


  -- grid refreshing
  m.grid_refresh=metro.init()
  m.grid_refresh.time=0.1
  m.grid_refresh.event=function()
    if m.grid_on then
      m:grid_redraw()
    end
  end
  m.grid_refresh:start()

  -- setup scale 
  local scale_names = {}
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  tab.print(scale_names)
  m.note_scale = MusicUtil.generate_scale_of_length(24, scale_names[1], 128)

  return m
end

function Mandoguitar:toggle_grid64_side()
  self.grid64default=not self.grid64default
end

function Mandoguitar:toggle_grid(on)
  if on==nil then
    self.grid_on=not self.grid_on
  else
    self.grid_on=on
  end
  if self.grid_on then
    self.g=grid.connect()
    self.g.key=function(x,y,z)
      print("mandoguitar grid: ",x,y,z)
      if self.grid_on then
        self:grid_key(x,y,z)
      end
    end
  else
    if self.toggle_callback~=nil then
      self.toggle_callback()
    end
  end
end

function Mandoguitar:set_toggle_callback(fn)
  self.toggle_callback=fn
end

function Mandoguitar:grid_key(x,y,z)
  self:key_press(y,x,z==1)
  self:grid_redraw()
end


function Mandoguitar:emit_note(division)
  local update=false
  for i=1,self.num_voices do
    if self.voices[i].is_playing and self.voices[i].division==division then
      self.voices[i].step=self.voices[i].step+1
      if self.voices[i].step>#self.voices[i].steps then
        self.voices[i].step=1
      end
      
      update=true
    end
  end
  if update then
    self:grid_redraw()
  end
end



function Mandoguitar:get_visual()
  --- update the blinky thing
  self.blink_count=self.blink_count+1
  if self.blink_count>1000 then
    self.blink_count=0
  end
  for i,_ in ipairs(self.blinky) do
    if i==1 then
      self.blinky[i]=1-self.blinky[i]
    else
      if self.blink_count%i==0 then
        self.blinky[i]=0
      else
        self.blinky[i]=1
      end
    end
  end

  -- clear visual, decaying the ntoes
  for row=1,8 do
    for col=1,self.grid_width do
      local voice = math.floor(col/9)+1
      if row < 8 and not self.voices[voice].in_menu then 
        if self.visual[row][col] > 0 then 
          self.visual[row][col] = self.visual[row][col] - 1
          if self.visual[row][col] < 0 then 
            self.visual[row][col] = 0
          end
        end
      else
        self.visual[row][col]=0
      end
    end
  end

  -- show if in menu
  for i=1,self.num_voices do
    if self.voices[i].in_menu then 
      self.visual[8][1+8*(i-1)] = 15
    end
  end

  -- illuminate currently pressed button
  for k,_ in pairs(self.pressed_buttons) do
    row,col=k:match("(%d+),(%d+)")
    self.visual[tonumber(row)][tonumber(col)]=15
  end

  return self.visual
end

function Mandoguitar:key_press(row,col,on)
  if self.grid64 and not self.grid64default then
    col=col+8
  end
  if on then
    self.pressed_buttons[row..","..col]=self:current_time()
    if row==8 and col==2 and self.toggleable then
      self.kill_timer=self:current_time()
    end
  else
    self.pressed_buttons[row..","..col]=nil
    if row==8 and col==2 and self.toggleable then
      self.kill_timer=self:current_time()-self.kill_timer
      if self.kill_timer>1 then
        print("switching!")
        self:toggle_grid(false)
      end
      self.kill_timer=0
    end
  end

  if row == 8 and (col==1 or col==9) and on then
    -- toggle menu
    self:toggle_menu(col)
  elseif (col < 9 and self.voices[1].in_menu) or (col >= 9 and self.voices[2].in_menu) then 
    -- do menu stuff
  else
    self:press_note(row,col,on)
  end
end

function Mandoguitar:toggle_menu(col)
  local voice = 1
  if col > 8 then 
    voice = 2
  end
  self.voices[voice].in_menu = not self.voices[voice].in_menu 
end

function Mandoguitar:press_note(row,col,on)
  local voice = 1
  if col > 8 then 
    col = col - 8
    voice = 2
  end
  local note = self.note_scale[4*(col-1)+(9-row)]
  if on then 
    mx:on({name="tatak piano",midi=note,velocity=120})
  else
    mx:off({name="tatak piano",midi=note})
  end
end

function Mandoguitar:current_time()
  return clock.get_beat_sec()*clock.get_beats()
end

function Mandoguitar:grid_redraw()
  self.g:all(0)
  local gd=self:get_visual()
  local s=1
  local e=self.grid_width
  local adj=0
  if self.grid64 then
    e=8
    if not self.grid64default then
      s=9
      e=16
      adj=-8
    end
  end
  for row=1,8 do
    for col=s,e do
      if gd[row][col]~=0 then
        self.g:led(col+adj,row,gd[row][col])
      end
    end
  end
  self.g:refresh()
end

return Mandoguitar
