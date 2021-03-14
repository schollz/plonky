print(_VERSION)
print(package.cpath)
if not string.find(package.cpath,"/home/we/dust/code/plonky/lib/") then
  package.cpath=package.cpath..";/home/we/dust/code/plonky/lib/?.so"
end
local json=require("cjson")
-- local json=include("plonky/lib/json") -- todo load faster library
-- local lattice=require("lattice")
local lattice=include("plonky/lib/lattice")
local MusicUtil=require "musicutil"

local mxsamples=nil
if util.file_exists(_path.code.."mx.samples") then
  mxsamples=include("mx.samples/lib/mx.samples")
end

local Plonky={}

function Plonky:new(args)
  local m=setmetatable({},{__index=Plonky})
  local args=args==nil and {} or args
  m.debug=false -- args.debug TODO remove this
  m.grid_on=args.grid_on==nil and true or args.grid_on
  m.toggleable=args.toggleable==nil and false or args.toggleable

  m.scene="a"


  -- initiate mx samples
  if mxsamples~=nil then
    self.mx=mxsamples:new()
    self.instrument_list=self.mx:list_instruments()
  else
    self.mx=nil
    self.instrument_list={}
  end

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

  -- define num voices
  m.num_voices=8
  m.voice_set=0 -- the current voice set
  m.disable_menu_reload=false

  -- keep track of pressed buttons
  m.pressed_buttons={} -- keep track of where fingers press
  m.pressed_notes={} -- arp and patterns
  for i=0,m.num_voices/2-1 do
    m.pressed_notes[i*2]={}
  end

  -- debounce engine switching
  m.updateengine=0

  -- setup step sequencer
  m.voices={}
  local vs=0
  for i=1,m.num_voices do
    m.voices[i]={
      voice_set=vs,
      division=8,-- 8 = quartner notes
      cluster={},
      pressed={},
      latched={},
      arp_last="",
      arp_step=1,
      record_steps={},
      record_step=1,
      record_step_adj=0,
      play_steps={},
      play_step=1,
      current_note="",
    }
    if i%2==0 then
      vs=vs+2
    end
  end

  -- setup lattice
  -- lattice
  -- for keeping time of all the divisions
  m.lattice=lattice:new({
    ppqn=64
  })
  m.timers={}
  m.divisions={1,2,4,6,8,12,16,24,32}
  m.division_names={"2","1","1/2","1/2t","1/4","1/4t","1/8","1/8t","1/16"}
  for _,division in ipairs(m.divisions) do
    m.timers[division]={}
    m.timers[division].lattice=m.lattice:new_pattern{
      action=function(t)
        m:emit_note(division,t)
      end,
    division=1/(division/2)}
  end


  -- grid refreshing
  m.grid_refresh=metro.init()
  m.grid_refresh.time=0.1
  m.grid_refresh.event=function()
    if m.updateengine>0 then
      m.updateengine=m.updateengine-1
      if m.updateengine==0 then
        m:update_engine()
      end
    end
    if m.grid_on then
      m:grid_redraw()
    end
  end

  -- setup scale
  m.scale_names={}
  for i=1,#MusicUtil.SCALES do
    table.insert(m.scale_names,string.lower(MusicUtil.SCALES[i].name))
  end


  -- initiate midi connections
  m.device={}
  m.device_list={"disabled"}
  for i,dev in pairs(midi.devices) do
    if dev.port~=nil then
      local name=string.lower(dev.name).." "..i
      table.insert(m.device_list,name)
      print("adding "..name.." to port "..dev.port)
      m.device[name]={
        name=name,
        port=dev.port,
        midi=midi.connect(dev.port),
      }
      m.device[name].midi.event=function(data)
        if name~=m.device_list[params:get("midi_transport")] then
          do return end
        end
        local msg=midi.to_msg(data)
        if msg.type=="clock" then do return end end
-- OP-1 fix for transport
        if msg.type=='start' or msg.type=='continue' then
          print(name.." starting clock")
          m.lattice:hard_restart()
          for i=1,m.num_voices do
            params:set(i.."play",1)
          end
        elseif msg.type=="stop" then
          print(name.." stopping clock")
          for i=1,m.num_voices do
            params:set(i.."play",0)
          end
        end
      end
    end
  end


  m:setup_params()
  m:build_scale()
  -- start up!
  m.grid_refresh:start()
  m.lattice:start()
  return m
end

function Plonky:update_voice_step(unity)
  self.voice_set=util.clamp(self.voice_set+2*unity,0,self.num_voices-2)
  -- if 1+self.voice_set~=params:get("voice") and 2+self.voice_set~=params:get("voice") then
  --   self.disable_menu_reload=true
  --   params:set("voice",self.voice_set+1)
  --   self.disable_menu_reload=false
  -- end
end

function Plonky:update_engine()
  local name=self.engine_options[params:get("mandoengine")]
  print("loading "..name)
  self.engine_loaded=false
  engine.load(name,function()
    self.engine_loaded=true
    print("loaded "..name)
    -- write this engine as last used for next default on startup
    f=io.open(_path.data.."plonky/engine","w")
    f:write(params:get("mandoengine"))
    f:close()
  end)
  engine.name=name
  self:reload_params(params:get("voice"))
end

function Plonky:reload_params(v)
  for _,param_name in ipairs(self.param_names) do
    for i=1,self.num_voices do
      if i==v then
        params:show(i..param_name)
      else
        params:hide(i..param_name)
      end
    end
  end
  for eng,param_list in pairs(self.engine_params) do
    if engine.name==eng then
      for _,param_name in ipairs(param_list) do
        for i=1,self.num_voices do
          if i==v then
            params:show(i..param_name)
          else
            params:hide(i..param_name)
          end
        end
      end
    else
      for _,param_name in ipairs(param_list) do
        for j=1,self.num_voices do
          params:hide(j..param_name)
        end
      end
    end
  end
end

function Plonky:setup_params()
  self.engine_loaded=false
  self.engine_options={"PolyPerc"}
  if mxsamples~=nil then
    table.insert(self.engine_options,"MxSamples")
  end
  self.param_names={"scale","root","tuning","division","engine_enabled","midi","legato","crow","midichannel"}
  self.engine_params={}
  self.engine_params["MxSamples"]={"mx_instrument","mx_velocity","mx_amp","mx_pan","mx_release"}
  self.engine_params["PolyPerc"]={"pp_amp","pp_pw","pp_cut","pp_release"}


  params:add_group("PLONKY",24*self.num_voices+2)
  params:add{type="number",id="voice",name="voice",min=1,max=self.num_voices,default=1,action=function(v)
    self:reload_params(v)
    if not self.disable_menu_reload then
      _menu.rebuild_params()
    end
  end}
  params:add_separator("outputs")
  for i=1,self.num_voices do
    -- midi out
    params:add{type="option",id=i.."engine_enabled",name="engine",options={"disabled","enabled"},default=2}
    params:add{type="option",id=i.."midi",name="midi out",options=self.device_list,default=1}
    params:add{type="number",id=i.."midichannel",name="midi ch",min=1,max=16,default=1}
    params:add{type="option",id=i.."crow",name="crow/JF",options={"disabled","crow out 1+2","crow out 3+4","crow ii JF"},default=1,action=function(v)
      if v==2 then
        crow.output[2].action="{to(5,0),to(0,0.25)}"
      elseif v==3 then
        crow.output[4].action="{to(5,0),to(0,0.25)}"
      elseif v==4 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  end
  params:add_separator("engine parameters")
  for i=1,self.num_voices do
    -- MxSamples parameters
    params:add{type="option",id=i.."mx_instrument",name="instrument",options=self.instrument_list,default=1}
    params:add{type="number",id=i.."mx_velocity",name="velocity",min=0,max=127,default=80}
    params:add {type='control',id=i.."mx_amp",name="amp",controlspec=controlspec.new(0,2,'lin',0.01,0.5,'amp',0.01/2)}
    params:add{type="control",id=i.."mx_pan",name="pan",controlspec=controlspec.new(-1,1,'lin',0,0)}
    params:add {type='control',id=i.."mx_release",name="release",controlspec=controlspec.new(0,10,'lin',0,2,'s')}
    -- PolyPerc parameters
    params:add{type="control",id=i.."pp_amp",name="amp",controlspec=controlspec.new(0,1,'lin',0,0.25,'')}
    params:add{type="control",id=i.."pp_pw",name="pw",controlspec=controlspec.new(0,100,'lin',0,50,'%')}
    params:add{type="control",id=i.."pp_release",name="release",controlspec=controlspec.new(0.1,3.2,'lin',0,1.2,'s')}
    params:add{type="control",id=i.."pp_cut",name="cutoff",controlspec=controlspec.new(50,5000,'exp',0,800,'hz')}
  end
  params:add_separator("plonky")
  for i=1,self.num_voices do
    params:add{type="option",id=i.."scale",name="scale",options=self.scale_names,default=1,action=function(v)
      self:build_scale()
    end}
    params:add{type="number",id=i.."root",name="root",min=0,max=36,default=24,formatter=function(param)
      return MusicUtil.note_num_to_name(param:get(),true)
    end,action=function(v)
      self:build_scale()
    end}
    params:add{type="number",id=i.."tuning",name="string tuning",min=0,max=7,default=5,formatter=function(param)
      return "+"..param:get()
    end,action=function(v)
      self:build_scale()
    end}
    params:add{type="option",id=i.."division",name="division",options=self.division_names,default=7}
    params:add{type="control",id=i.."legato",name="legato",controlspec=controlspec.new(1,99,'lin',1,50,'%')}
    params:add{type="binary",id=i.."arp",name="arp",behavior="toggle",default=0}
    params:hide(i.."arp")
    params:add{type="binary",id=i.."latch",name="latch",behavior="toggle",default=0,action=function(v)
      if v==1 then
        -- load latched steps
        if params:get(i.."latch_steps")~="" and params:get(i.."latch_steps")~="[]" then
          self.voices[i].latched=json.decode(params:get(i.."latch_steps"))
        end
      end
    end}
    params:hide(i.."latch")
    params:add{type="binary",id=i.."mute_non_arp",name="mute non-arp",behavior="toggle",default=0}
    params:hide(i.."mute_non_arp")
    params:add{type="binary",id=i.."record",name="record pattern",behavior="toggle",default=0,action=function(v)
      if v==1 then
        self.voices[i].record_step=0
        self.voices[i].record_step_adj=0
        self.voices[i].record_steps={}
        self.voices[i].cluster={}
      elseif v==0 and self.voices[i].record_step>0 then
        if self.debug then
          print(json.encode(self.voices[i].record_steps))
        end
        params:set(i.."play_steps",json.encode(self.voices[i].record_steps))
      end
    end}
    params:hide(i.."record")
    params:add{type="binary",id=i.."play",name="play",behavior="toggle",action=function(v)
      if v==1 then
        if params:get(i.."play_steps")~="[]" and params:get(i.."play_steps")~="" then
          if self.debug then print("playing "..i) end
          self.voices[i].play_steps=json.decode(params:get(i.."play_steps"))
          self.voices[i].play_step=0
        else
          params:set(i.."play",0)
        end
      else
        print("stopping "..i)
      end
    end}
    params:hide(i.."play")
    params:add_text(i.."play_steps",i.."play_steps","")
    params:hide(i.."play_steps")
    params:add_text(i.."latch_steps",i.."latch_steps","[]")
    params:hide(i.."latch_steps")
  end
  -- read in the last used engine as the default
  if util.file_exists(_path.data.."plonky/engine") then
    local f=io.open(_path.data.."plonky/engine","rb")
    local content=f:read("*all")
    f:close()
    print(content)
    params:set("mandoengine",tonumber(content))
  end
  params:add{type="option",id="mandoengine",name="engine",options=self.engine_options,action=function()
    self.updateengine=4
  end}
  params:add{type="option",id="midi_transport",name="midi transport",options=self.device_list,default=1}


  self:reload_params(1)
  self:update_engine()
end

function Plonky:reset_toggles()
  print("resetting toggles")
  for i=1,self.num_voices do
    params:set(i.."play",0)
    params:set(i.."mute_non_arp",0)
    params:set(i.."record",0)
    params:set(i.."arp",0)
    params:set(i.."latch",0)
  end
end

function Plonky:build_scale()
  for i=1,self.num_voices do
    self.voices[i].scale=MusicUtil.generate_scale_of_length(params:get(i.."root"),self.scale_names[params:get(i.."scale")],168)
  end
  print("scale start: "..self.voices[1].scale[1])
  print("scale start: "..self.voices[2].scale[1])
end

function Plonky:toggle_grid64_side()
  self.grid64default=not self.grid64default
end

function Plonky:toggle_grid(on)
  if on==nil then
    self.grid_on=not self.grid_on
  else
    self.grid_on=on
  end
  if self.grid_on then
    self.g=grid.connect()
    self.g.key=function(x,y,z)
      print("plonky grid: ",x,y,z)
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

function Plonky:set_toggle_callback(fn)
  self.toggle_callback=fn
end

function Plonky:grid_key(x,y,z)
  self:key_press(y,x,z==1)
  self:grid_redraw()
end


function Plonky:emit_note(division,step)
  local update=false
  for i=1,self.num_voices do
    if params:get(i.."play")==1 and self.divisions[params:get(i.."division")]==division then
      local num_steps=#self.voices[i].play_steps
      self.voices[i].play_step=self.voices[i].play_step+1
      if self.debug then
        print("playing step "..self.voices[i].play_step.."/"..num_steps)
      end
      if self.voices[i].play_step>num_steps then
        self.voices[i].play_step=1
      end
      local ind=self.voices[i].play_step
      local ind2=self.voices[i].play_step+1
      if ind2>num_steps then
        ind2=1
      end
      local rcs=self.voices[i].play_steps[ind]
      local rcs_next=self.voices[i].play_steps[ind2]
      if rcs~=nil and rcs_next~=nil then
        if rcs[1]~="-" and rcs[1]~="." then
          self.voices[i].play_last={}
          for _,key in ipairs(rcs) do
            local row,col=key:match("(%d+),(%d+)")
            row=tonumber(row)
            col=tonumber(col)
            self:press_note(self.voices[i].voice_set,row,col,true)
            table.insert(self.voices[i].play_last,{row,col})
          end
        end
        if rcs_next[1]~="-" and self.voices[i].play_last~=nil then
          clock.run(function()
            local play_last=self.voices[i].play_last
            clock.sleep(clock.get_beat_sec()/(division/2)*params:get(i.."legato")/100)
            for _,rc in ipairs(play_last) do
              self:press_note(self.voices[i].voice_set,rc[1],rc[2],false)
            end
            self.voices[i].play_last=nil
          end)
        end
        update=true
      end
    end
    if params:get(i.."arp")==1 and self.divisions[params:get(i.."division")]==division then
      local keys={}
      local keys_len=0
      if params:get(i.."latch")==1 then
        keys=self.voices[i].latched
        keys_len=#keys
      else
        keys,keys_len=self:get_keys_sorted_by_value(self.voices[i].pressed)
      end
      if keys_len>0 then
        local key=keys[1]
        local key_next=keys[2]
        if keys_len>1 then
          key=keys[(self.voices[i].arp_step)%keys_len+1]
          key_next=keys[(self.voices[i].arp_step+1)%keys_len+1]
        end
        local row,col=key:match("(%d+),(%d+)")
        row=tonumber(row)
        col=tonumber(col)
        self:press_note(self.voices[i].voice_set,row,col,true)
        clock.run(function()
          clock.sleep(clock.get_beat_sec()/(division/2)*params:get(i.."legato")/100)
          self:press_note(self.voices[i].voice_set,row,col,false)
        end)
        self.voices[i].arp_step=self.voices[i].arp_step+1
      end
      update=true
    end
  end
  if update then
    self:grid_redraw()
    redraw()
  end
end


function Plonky:get_visual()
  -- clear visual, decaying the ntoes
  for row=1,8 do
    for col=1,self.grid_width do
      if self.visual[row][col]>0 then
        self.visual[row][col]=self.visual[row][col]-1
        if self.visual[row][col]<0 then
          self.visual[row][col]=0
        end
      end
    end
  end

  local voice_pair={1+self.voice_set,2+self.voice_set}

  -- show latched
  for i=voice_pair[1],voice_pair[2] do
    local intensity=2
    if params:get(i.."latch")==1 then
      intensity=10
    end
    for _,k in ipairs(self.voices[i].latched) do
      local row,col=k:match("(%d+),(%d+)")
      if self.visual[tonumber(row)][tonumber(col)]==0 then
        self.visual[tonumber(row)][tonumber(col)]=intensity
      end
    end
  end

  -- illuminate currently pressed buttons
  for k,_ in pairs(self.pressed_buttons) do
    local row,col=k:match("(%d+),(%d+)")
    self.visual[tonumber(row)][tonumber(col)]=10
  end

  -- illuminate currently pressed notes
  for k,_ in pairs(self.pressed_notes[self.voice_set]) do
    local row,col=k:match("(%d+),(%d+)")
    self.visual[tonumber(row)][tonumber(col)]=10
  end
  -- finger pressed notes
  for i=voice_pair[1],voice_pair[2] do
    self.voices[i].current_note=""
    for _,k in ipairs(self:get_keys_sorted_by_value(self.voices[i].pressed)) do
      local row,col=k:match("(%d+),(%d+)")
      row=tonumber(row)
      col=tonumber(col)
      self.visual[row][col]=15
      local note=self:get_note_from_pos(i,row,col)
      self.voices[i].current_note=self.voices[i].current_note.." "..MusicUtil.note_num_to_name(note,true)
    end
  end



  return self.visual
end

function Plonky:record_add_rest_or_legato(voice)
  if params:get(voice.."record")==0 then
    do return end
  end
  local wtd="." -- rest
  if self.debug then
    print("cluster ",json.encode(self.voices[voice].cluster))
    print("record_steps ",json.encode(self.voices[voice].record_steps))
  end

  if next(self.voices[voice].cluster)~=nil then
    wtd="-"
    self.voices[voice].record_steps[self.voices[voice].record_step]=self.voices[voice].cluster
    self.voices[voice].cluster={}
  elseif next(self.voices[voice].record_steps)~=nil and self.voices[voice].record_steps[#self.voices[voice].record_steps][1]=="-" and next(self.voices[voice].pressed)~=nil and next(self.voices[voice].cluster)==nil then
    wtd="-"
  end
  self:record_update_step(voice)
  self.voices[voice].record_steps[self.voices[voice].record_step]={wtd}
end

function Plonky:record_update_step(voice)
  if self.debug then
    print("record_update_step",json.encode(self.voices[voice].record_steps))
  end
  self.voices[voice].record_step=self.voices[voice].record_step+1

  -- check adjustment
  if self.voices[voice].record_step_adj==0 then do return end end
-- erase steps
  -- local last=self.voices[voice].record_steps[#self.voices[voice].record_steps]
  for i=self.voices[voice].record_step_adj,0 do
    self.voices[voice].record_steps[self.voices[voice].record_step+i]=nil
  end
  if self.voices[voice].record_steps==nil then
    self.voices[voice].record_steps={}
  end
  self.voices[voice].record_step=self.voices[voice].record_step+self.voices[voice].record_step_adj-1
  -- self.voices[voice].record_steps[self.voices[voice].record_step]=last
  self.voices[voice].record_step=self.voices[voice].record_step+1
  self.voices[voice].record_step_adj=0
  if self.debug then
    print("record_update_step (adj)",json.encode(self.voices[voice].record_steps))
  end
end

function Plonky:key_press(row,col,on)
  if self.grid64 and not self.grid64default then
    col=col+8
  end

  local ct=self:current_time()
  local rc=row..","..col
  if on then
    self.pressed_buttons[rc]=ct
  else
    self.pressed_buttons[rc]=nil
  end


  -- determine voice
  local voice=1+self.voice_set
  if col>8 then
    voice=2+self.voice_set
  end

  if params:get("voice")~=voice and _menu.mode then
    params:set("voice",voice)
  end

  -- add to note cluster
  if on then
    self.voices[voice].pressed[rc]=ct
    if params:get(voice.."record")==1 and next(self.voices[voice].cluster)==nil then
      self:record_update_step(voice)
    end
    table.insert(self.voices[voice].cluster,rc)
  else
    self.voices[voice].pressed[rc]=nil
    local num_pressed=0
    for k,_ in pairs(self.voices[voice].pressed) do
      num_pressed=num_pressed+1
    end
    if num_pressed==0 then
      -- add the previous presses to note cluster
      if params:get(voice.."record")==1 then
        if next(self.voices[voice].cluster)~=nil then
          self.voices[voice].record_steps[self.voices[voice].record_step]=self.voices[voice].cluster
        end
        if self.debug then
          print(json.encode(self.voices[voice].record_steps))
        end
      else
        self.voices[voice].latched=self.voices[voice].cluster
        params:set(voice.."latch_steps",json.encode(self.voices[voice].cluster))
      end
      -- reset cluster
      self.voices[voice].cluster={}
    end
  end

  self:press_note(self.voice_set,row,col,on,true)
end


function Plonky:press_note(voice_set,row,col,on,is_finger)
  if on then
    self.pressed_notes[voice_set][row..","..col]=true
  else
    self.pressed_notes[voice_set][row..","..col]=nil
  end

  -- determine voice
  local voice=1+voice_set
  if col>8 then
    voice=2+voice_set
  end

  -- determine if muted
  if is_finger~=nil and is_finger then
    if params:get(voice.."arp")==1 and params:get(voice.."mute_non_arp")==1 then
      do return end
    end
  end

  -- determine note
  local note=self:get_note_from_pos(voice,row,col)
  if self.debug then
    print("voice "..voice.." press note "..MusicUtil.note_num_to_name(note,true))
  end

  -- play from engine
  if not self.engine_loaded then
    do return end
  end
  if params:get(voice.."engine_enabled")==2 then
    if engine.name=="MxSamples" then
      if on then
        self.mx:on({
          name=self.instrument_list[params:get(voice.."mx_instrument")],
          midi=note,
          velocity=params:get(voice.."mx_velocity"),
          amp=params:get(voice.."mx_amp"),
          release=params:get(voice.."mx_release"),
          pan=params:get(voice.."mx_pan"),
        })
      else
        self.mx:off({name=self.instrument_list[params:get(voice.."mx_instrument")],midi=note})
      end
    elseif engine.name=="PolyPerc" then
      if on then
        engine.amp(params:get(voice.."pp_amp"))
        engine.release(params:get(voice.."pp_release"))
        engine.cutoff(params:get(voice.."pp_cut"))
        engine.pw(params:get(voice.."pp_pw")/100)
        engine.hz(MusicUtil.note_num_to_freq(note))
      end
    end
  end

  -- play on midi device
  if params:get(voice.."midi")>1 then
    if on then
      if self.debug then
        print(note.." -> "..self.device_list[params:get(voice.."midi")])
      end
      self.device[self.device_list[params:get(voice.."midi")]].midi:note_on(note,80,params:get(voice.."midichannel"))
    else
      self.device[self.device_list[params:get(voice.."midi")]].midi:note_off(note,80,params:get(voice.."midichannel"))
    end
  end

  -- play on crow
  if params:get(voice.."crow")>1 and on then
    if params:get(voice.."crow")==2 then
      crow.output[1].volts=(note-60)/12
      crow.output[2].execute()
    elseif params:get(voice.."crow")==3 then
      crow.output[3].volts=(note-60)/12
      crow.output[4].execute()
    elseif params:get(voice.."crow")==4 then
      crow.ii.jf.play_note((note-60)/12,5)
    end
  end
end

function Plonky:get_cluster(voice)
  s=""
  for _,rc in ipairs(self.voices[voice].cluster) do
    local row,col=rc:match("(%d+),(%d+)")
    row=tonumber(row)
    col=tonumber(col)
    local note_name=rc
    if col~=nil and row~=nil then
      local note=self:get_note_from_pos(voice,row,col)
      note_name=MusicUtil.note_num_to_name(note,true)
    end
    s=s..note_name.." "
  end
  return s
end

function Plonky:get_note_from_pos(voice,row,col)
  if voice%2==0 then
    col=col-8
  end
  return self.voices[voice].scale[(params:get(voice.."tuning")-1)*(col-1)+(9-row)]
end

function Plonky:get_keys_sorted_by_value(tbl)
  sortFunction=function(a,b) return a<b end

  local keys={}
  local keys_length=0
  for key in pairs(tbl) do
    keys_length=keys_length+1
    table.insert(keys,key)
  end

  table.sort(keys,function(a,b)
    return sortFunction(tbl[a],tbl[b])
  end)

  return keys,keys_length
end

function Plonky:get_keys_sorted_by_key(tbl)
  sortFunction=function(a,b) return a<b end

  local keys={}
  local keys_length=0
  for key in pairs(tbl) do
    keys_length=keys_length+1
    table.insert(keys,key)
  end

  table.sort(keys,function(a,b)
    return sortFunction(a,b)
  end)

  return keys,keys_length
end

function Plonky:current_time()
  return clock.get_beat_sec()*clock.get_beats()
end

function Plonky:grid_redraw()
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

function Plonky:calculate_lfo(period_in_beats,offset)
  if period_in_beats==0 then
    return 1
  else
    return math.sin(2*math.pi*clock.get_beats()/period_in_beats+offset)
  end
end


return Plonky
