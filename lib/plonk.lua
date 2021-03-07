local json=include("plonk/lib/json") -- todo load faster library
local lattice=require("lattice")
local MusicUtil=require "musicutil"

local mxsamples=nil
if util.file_exists(_path.code.."mx.samples") then
  mxsamples=include("mx.samples/lib/mx.samples")
end

local Plonk={}
local divisions={1,2,4,6,8,12,16,24,32}
local division_names={"2 wn","wn","hn","hn-t","qn","qn-t","eighth","16-t","16"}

function Plonk:new(args)
  local m=setmetatable({},{__index=Plonk})
  local args=args==nil and {} or args
  m.debug=true -- args.debug TODO remove this
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

  -- debouncing and blinking
  m.blink_count=0
  m.blinky={}
  for i=1,m.grid_width do
    m.blinky[i]=1 -- 1 = fast, 16 = slow
  end

  -- keep track of pressed buttons
  m.pressed_buttons={} -- keep track of where fingers press
  m.pressed_notes={} -- arp and patterns

  -- debounce engine switching
  m.updateengine=0

  -- define num voices
  m.num_voices=2

  -- setup step sequencer
  m.voices={}
  for i=1,m.num_voices do
    m.voices[i]={
      division=8,-- 8 = quartner notes
      steps={},
      step=0,
      step_val=0,
      pitch_mod_i=5,
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
  m.grid_refresh:start()

  -- setup scale
  m.scale_names={}
  for i=1,#MusicUtil.SCALES do
    table.insert(m.scale_names,string.lower(MusicUtil.SCALES[i].name))
  end

  m:setup_params()
  m:build_scale()
  return m
end

function Plonk:update_engine()
  local name=self.engine_options[params:get("mandoengine")]
  print("loading "..name)
  self.engine_loaded=false
  engine.load(name,function()
    self.engine_loaded=true
    print("loaded "..name)
    -- write this engine as last used for next default on startup
    f=io.open(_path.data.."plonk/engine","w")
    f:write(params:get("mandoengine"))
    f:close()
  end)
  engine.name=name
  self:reload_params(params:get("voice"))
end

function Plonk:reload_params(v)
  for _,param_name in ipairs(self.param_names) do
    params:show(v..param_name)
    params:hide((3-v)..param_name)
  end
  for eng,param_list in pairs(self.engine_params) do
    if engine.name==eng then
      for _,param_name in ipairs(param_list) do
        params:show(v..param_name)
        params:hide((3-v)..param_name)
      end
    else
      for _,param_name in ipairs(param_list) do
        for j=1,2 do
          params:hide(j..param_name)
        end
      end
    end
  end
end

function Plonk:setup_params()
  self.engine_loaded=false
  self.engine_options={"PolyPerc"}
  if mxsamples~=nil then
    table.insert(self.engine_options,"MxSamples")
  end
  self.param_names={"scale","root","tuning","arp","latch","division","record","play"}
  self.engine_params={}
  self.engine_params["MxSamples"]={"mx_instrument","mx_velocity"}
  self.engine_params["PolyPerc"]={"pp_amp","pp_pw","pp_cut","pp_release"}


  params:add_group("MANDOGUITAR",15*2+2)
  params:add{type="option",id="mandoengine",name="engine",options=self.engine_options,action=function()
    self.updateengine=4
  end}
  params:add{type="number",id="voice",name="voice",min=1,max=2,default=1,action=function(v)
    self:reload_params(v)
    _menu.rebuild_params()
  end}
  for i=1,self.num_voices do
    -- MxSamples parameters
    params:add{type="option",id=i.."mx_instrument",name="instrument",options=self.instrument_list,default=10}
    params:add{type="number",id=i.."mx_velocity",name="velocity",min=0,max=127,default=80}
    -- PolyPerc parameters
    params:add{type="control",id=i.."pp_amp",name="amp",controlspec=controlspec.new(0,1,'lin',0,0.5,'')}
    params:add{type="control",id=i.."pp_pw",name="pw",controlspec=controlspec.new(0,100,'lin',0,50,'%')}
    params:add{type="control",id=i.."pp_release",name="release",controlspec=controlspec.new(0.1,3.2,'lin',0,1.2,'s')}
    params:add{type="control",id=i.."pp_cut",name="cutoff",controlspec=controlspec.new(50,5000,'exp',0,800,'hz')}
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
    params:add{type="option",id=i.."division",name="division",options=division_names,default=7}
    params:add{type="binary",id=i.."arp",name="arp",behavior="toggle",default=0}
    params:add{type="binary",id=i.."latch",name="latch",behavior="toggle",default=0}
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
    params:add{type="binary",id=i.."play",name="play",behavior="toggle",action=function(v)
      if v==1 then
        if params:get(i.."play_steps")~="[]" and params:get(i.."play_steps")~="" then
          print("playing "..i)
          self.voices[i].play_steps=json.decode(params:get(i.."play_steps"))
          self.voices[i].play_step=0
        else
          params:set(i.."play",0)
        end
      else
        print("stopping "..i)
      end
    end}
    params:add_text(i.."play_steps",i.."play_steps","")
    params:hide(i.."play_steps")
  end
  -- read in the last used engine as the default
  if util.file_exists(_path.data.."plonk/engine") then
    local f=io.open(_path.data.."plonk/engine","rb")
    local content=f:read("*all")
    f:close()
    print(content)
    params:set("mandoengine",tonumber(content))
  end

  self:reload_params(1)
  self:update_engine()
end

function Plonk:build_scale()
  for i=1,2 do
    self.voices[i].scale=MusicUtil.generate_scale_of_length(params:get(i.."root"),self.scale_names[params:get(i.."scale")],168)
  end
  print("scale start: "..self.voices[1].scale[1])
  print("scale start: "..self.voices[2].scale[1])
end

function Plonk:toggle_grid64_side()
  self.grid64default=not self.grid64default
end

function Plonk:toggle_grid(on)
  if on==nil then
    self.grid_on=not self.grid_on
  else
    self.grid_on=on
  end
  if self.grid_on then
    self.g=grid.connect()
    self.g.key=function(x,y,z)
      print("plonk grid: ",x,y,z)
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

function Plonk:set_toggle_callback(fn)
  self.toggle_callback=fn
end

function Plonk:grid_key(x,y,z)
  self:key_press(y,x,z==1)
  self:grid_redraw()
end


function Plonk:emit_note(division,step)
  local update=false
  for i=1,self.num_voices do
    if params:get(i.."play")==1 and divisions[params:get(i.."division")]==division then
      local num_steps=#self.voices[i].play_steps
      self.voices[i].play_step=self.voices[i].play_step+1
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
        print("----------")
        print(ind,"rcs",json.encode(rcs))
        print(ind2,"rcs_next",json.encode(rcs_next))
        if rcs[1]~="-" and rcs[1]~="." then
          self.voices[i].play_last={}
          for _,key in ipairs(rcs) do
            local row,col=key:match("(%d+),(%d+)")
            row=tonumber(row)
            col=tonumber(col)
            print("playing",row,col)
            self:press_note(row,col,true)
            table.insert(self.voices[i].play_last,{row,col})
          end
        end
        if rcs_next[1]~="-" and self.voices[i].play_last~=nil then
          clock.run(function()
            clock.sleep(clock.get_beat_sec()/(division/2)*0.5)
            for _,rc in ipairs(self.voices[i].play_last) do
              self:press_note(rc[1],rc[2],false)
            end
            self.voices[i].play_last=nil
          end)
        end
        update=true
      end
    end
    if params:get(i.."arp")==1 and divisions[params:get(i.."division")]==division then
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
        self:press_note(row,col,true)
        clock.run(function()
          clock.sleep(clock.get_beat_sec()/(division/2)*0.5)
          self:press_note(row,col,false)
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


function Plonk:get_visual()
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
      if self.visual[row][col]>0 then
        self.visual[row][col]=self.visual[row][col]-1
        if self.visual[row][col]<0 then
          self.visual[row][col]=0
        end
      end
    end
  end


  for i=1,self.num_voices do
  end

  -- show latched
  for i=1,self.num_voices do
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
  for k,_ in pairs(self.pressed_notes) do
    local row,col=k:match("(%d+),(%d+)")
    self.visual[tonumber(row)][tonumber(col)]=10
  end
  -- finger pressed notes
  for i=1,2 do
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

function Plonk:record_add_rest_or_legato(voice)
  if params:get(voice.."record")==0 then do return end end
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

function Plonk:record_update_step(voice)
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

function Plonk:key_press(row,col,on)
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
  local voice=1
  if col>8 then
    voice=2
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
      end
      -- reset cluster
      self.voices[voice].cluster={}
    end
  end

  self:press_note(row,col,on)
end


function Plonk:press_note(row,col,on)
  if on then
    self.pressed_notes[row..","..col]=true
  else
    self.pressed_notes[row..","..col]=nil
  end

  -- determine voice
  local voice=1
  if col>8 then
    voice=2
  end

  -- determine note
  local note=self:get_note_from_pos(voice,row,col)

  -- play from engine
  if not self.engine_loaded then
    do return end
  end
  if engine.name=="MxSamples" then
    if on then
      self.mx:on({name=self.instrument_list[params:get(voice.."mx_instrument")],midi=note,velocity=params:get(voice.."mx_velocity")})
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

function Plonk:get_cluster(voice)
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

function Plonk:get_note_from_pos(voice,row,col)
  if voice==2 then
    col=col-8
  end
  return self.voices[voice].scale[(params:get(voice.."tuning")-1)*(col-1)+(9-row)]
end

function Plonk:get_keys_sorted_by_value(tbl)
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

function Plonk:get_keys_sorted_by_key(tbl)
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

function Plonk:current_time()
  return clock.get_beat_sec()*clock.get_beats()
end

function Plonk:grid_redraw()
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

function Plonk:calculate_lfo(period_in_beats,offset)
  if period_in_beats==0 then
    return 1
  else
    return math.sin(2*math.pi*clock.get_beats()/period_in_beats+offset)
  end
end

return Plonk
