-- local json=include("mandoguitar/lib/json")
local lattice=require("lattice")
local MusicUtil = require "musicutil"
local mxsamples=include("mx.samples/lib/mx.samples")


engine.name="MxSamples" -- default engine

local Mandoguitar={}
local divisions={1,2,4,6,8,12,16,24,32}
local division_names={"2 wn","wn","hn","hn-t","qn","qn-t","eighth","16-t","16"}

function Mandoguitar:new(args)
  local m=setmetatable({},{__index=Mandoguitar})
  local args=args==nil and {} or args
  m.debug = true -- args.debug TODO remove this
  m.grid_on=args.grid_on==nil and true or args.grid_on
  m.toggleable=args.toggleable==nil and false or args.toggleable

  m.scene="a"

  -- initiate mx samples
  self.mx=mxsamples:new()
  self.instrument_list = self.mx:list_instruments()

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
  m.pressed_buttons={} -- keep track of where fingers press
  m.pressed_notes={} -- keep track of all notes on (from seqeuencer + fingers)

  -- define num voices
  m.num_voices=2

  -- setup step sequencer
  m.voices={}
  for i=1,m.num_voices do
    m.voices[i]={
      division=8,-- 8 = quartner notes
      is_playing=false,
      is_recording=false,
      steps={},
      step=0,
      step_val=0,
      pitch_mod_i=5,
      cluster={},
      pressed={},
      latched={},
      arp_step=1,
    }
  end

  -- setup lattice
  -- lattice
  -- for keeping time of all the divisions
  m.lattice=lattice:new({
    ppqn=64
  })
  m.timers={}
  for _,division in ipairs(divisions) do
    m.timers[division]={}
    m.timers[division].lattice=m.lattice:new_pattern{
      action=function(t)
        m:emit_note(division,t)
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
  m.scale_names = {}
  for i = 1, #MusicUtil.SCALES do
    table.insert(m.scale_names, string.lower(MusicUtil.SCALES[i].name))
  end

  m:setup_params()
  m:build_scale()
  return m
end

function Mandoguitar:setup_params()
  local param_names = {"scale","root","tuning","arp","latch","division","record","play"}
  
  self.engine_options = {"MxSamples","PolyPerc"}
  self.engine_loaded = true
  params:add_group("MANDOGUITAR",9*2+3)
  params:add{type="option",id="mandoengine",name="mandoengine",options=self.engine_options}
  params:add{type='binary',name='change engine',id='change engine',behavior='trigger',action=function(v)
    local name = self.engine_options[params:get("mandoengine")]
    print("loading "..name)
    self.engine_loaded = false
    engine.load(name, function()
      self.engine_loaded = true
      print("loaded "..name)
    end)
    engine.name=name
  end}
  params:add_separator("voices")
  params:add{type="number",id="voice",name="voice",min=1,max=2,default=1,action=function(v)
    for _, param_name in ipairs(param_names) do
      params:show(v..param_name)
      params:hide((3-v)..param_name)
    end
    if self.engine_options[params:get("mandoengine")]=="MxSamples" then 
      params:show(v.."mx_instrument")
      params:hide((3-v).."mx_instrument")
    end

    _menu.rebuild_params()
  end}
  for i=1,self.num_voices do 
    params:add{type="option",id=i.."mx_instrument",name ="instrument",options=self.instrument_list,default=10}
    params:add{type="option",id=i.."scale",name ="scale",options=self.scale_names,default=1,action=function(v)
      self:build_scale()
    end}
    params:add{type="number",id=i.."root",name="root",min=0,max=36,default=24,formatter=function(param)
       return MusicUtil.note_num_to_name(param:get(), true)
    end,action=function(v)
      self:build_scale()
    end}
    params:add{type="number",id=i.."tuning",name="string tuning",min=0,max=7,default=5,formatter=function(param)
       return "+"..param:get()
    end,action=function(v)
      self:build_scale()
    end}
    params:add{type="option",id=i.."division",name="division",options=division_names,default=7}
    params:add{type="binary",id=i.."arp",name="arp",behavior="toggle",default=0}
    params:add{type="binary",id=i.."latch",name="latch",behavior="toggle",default=0}
    params:add{type="binary",id=i.."record",name="record pattern",behavior="toggle"}
    params:add{type="binary",id=i.."play",name="play",behavior="toggle"}
  end
  for _, param_name in ipairs(param_names) do
    params:hide("2"..param_name)
  end
  params:hide("2mx_instrument")
end

function Mandoguitar:build_scale()
  for i=1,2 do 
    self.voices[i].scale = MusicUtil.generate_scale_of_length(params:get(i.."root"), self.scale_names[params:get(i.."scale")], 128)
  end
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


function Mandoguitar:emit_note(division,step)
  local update=false
  for i=1,self.num_voices do
    if params:get(i.."play")==1 and divisions[params:get(i.."division")]==division then
      self.voices[i].step=self.voices[i].step+1
      if self.voices[i].step>#self.voices[i].steps then
        self.voices[i].step=1
      end
      
      update=true
    end
    if params:get(i.."arp")==1 and divisions[params:get(i.."division")]==division then
      local keys = {}
      local keys_len = 0
      if params:get(i.."latch")==1 then 
        keys = self.voices[i].latched
        keys_len = #keys
      else
         keys,keys_len = self:get_notes_down(i)
      end
      if keys_len > 0 then 
        local key = keys[1]
        if keys_len > 1 then 
          key = keys[(self.voices[i].arp_step)%keys_len+1]
        end
        local row,col=key:match("(%d+),(%d+)")
        row = tonumber(row)
        col = tonumber(col)
        self:press_note(row,col,true)
        clock.run(function()
          clock.sleep(clock.get_beat_sec()/(division/2)*0.5)
          self:press_note(row,col,false)
        end)
        self.voices[i].arp_step = self.voices[i].arp_step+1
      end
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
      if self.visual[row][col] > 0 then 
        self.visual[row][col] = self.visual[row][col] - 1
        if self.visual[row][col] < 0 then 
          self.visual[row][col] = 0
        end
      end
    end
  end

  for i=1,self.num_voices do
  end

  -- show latched
  for i=1,self.num_voices do
    if params:get(i.."latch") == 1 then
      for _, k in ipairs(self.voices[i].latched) do 
        local row,col=k:match("(%d+),(%d+)")
        self.visual[tonumber(row)][tonumber(col)]=10        
      end
    end
  end

  -- illuminate currently pressed buttons
  for k,_ in pairs(self.pressed_buttons) do
    local row,col=k:match("(%d+),(%d+)")
    self.visual[tonumber(row)][tonumber(col)]=10
  end

  -- illuminate currently pressed notes
  for k,_ in pairs(self.pressed_notes) do
    local row,col=k:match("(%d+),(%d+)")
    self.visual[tonumber(row)][tonumber(col)]=15
  end



  return self.visual
end

function Mandoguitar:key_press(row,col,on)
  if self.grid64 and not self.grid64default then
    col=col+8
  end

  local ct = self:current_time()
  local rc = row..","..col
  if on then
    self.pressed_buttons[rc]=ct
  else
    self.pressed_buttons[rc]=nil
  end


  -- determine voice
  local voice = 1
  if col > 8 then 
    voice = 2
  end

  -- add to note cluster
  if on then 
    self.voices[voice].pressed[rc]=ct
    table.insert(self.voices[voice].cluster,rc)
  else
    self.voices[voice].pressed[rc]=nil
    local num_pressed = 0 
    for k, _ in pairs(self.voices[voice].pressed) do
      num_pressed = num_pressed + 1
    end
    if num_pressed == 0 then 
      -- add the previous presses to note cluster 
      self.voices[voice].latched = {}
      for _, c in ipairs(self.voices[voice].cluster) do 
        table.insert(self.voices[voice].latched,c)
      end
      -- reset cluster
      self.voices[voice].cluster = {}
    end
  end

  self:press_note(row,col,on)
end

function Mandoguitar:press_note(row,col,on)
  if on then
    self.pressed_notes[row..","..col]=self:current_time()
  else
    self.pressed_notes[row..","..col]=nil
  end

  -- determine voice
  local voice = 1
  if col > 8 then 
    col = col - 8
    voice = 2
  end

  -- determine note
  local note = self:get_note_from_pos(voice,row,col)

  -- play from engine
  if not self.engine_loaded then 
    do return end 
  end
  if self.engine_options[params:get("mandoengine")] == "MxSamples" then
    if on then 
      local velocity = 80
      print(note,velocity)
      self.mx:on({name=self.instrument_list[params:get(voice.."mx_instrument")],midi=note,velocity=velocity})
    else
      self.mx:off({name=self.instrument_list[params:get(voice.."mx_instrument")],midi=note})
    end    
  elseif self.engine_options[params:get("mandoengine")] == "PolyPerc"  then
    if on then 
      engine.amp(0.5)
      engine.hz(MusicUtil.note_num_to_freq(note))
    end
  end
end

function Mandoguitar:get_note_from_pos(voice,row,col)
  return self.voices[voice].scale[(params:get(voice.."tuning")-1)*(col-1)+(9-row)]
end

function Mandoguitar:get_notes_down(voice)
  sortFunction = function(a, b) return a < b end
  local tbl = self.voices[voice].pressed

  local keys = {}
  local keys_length=0
  for key in pairs(tbl) do
    keys_length = keys_length +1
    table.insert(keys, key)
  end

  table.sort(keys, function(a, b)
    return sortFunction(tbl[a], tbl[b])
  end)

  return keys, keys_length
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

function Mandoguitar:calculate_lfo(period_in_beats,offset)
  if period_in_beats==0 then
    return 1
  else
    return math.sin(2*math.pi*clock.get_beats()/period_in_beats+offset)
  end
end

return Mandoguitar
