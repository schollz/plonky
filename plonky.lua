-- plonky v1.2.0
-- keyboard + sequencer
--
-- llllllll.co/t/plonky
--
--
--
--    ▼ instructions below ▼
--
-- k1+(k2 or k3) records pattern
-- k2 or k3 plays pattern
-- (e2 or e3) changes latch/arp



local plonky=include("plonky/lib/plonky")
local shift=false
local arplatch=0

function init()
  mg=plonky:new({grid_on=true,toggleable=true})

  drawing=metro.init()
  drawing.time=0.1
  drawing.count=-1
  drawing.event=function()
    redraw()
  end
  drawing:start()
end



function enc(k,d)
  if k>1 and params:get((k-1).."record")==0 then
    -- toggle arp/latch
    d=sign(d)
    arplatch=util.clamp(arplatch+d,0,3)
    if arplatch==0 then
      params:set((k-1).."arp",0)
      params:set((k-1).."latch",0)
      params:set((k-1).."mute_non_arp",0)
    elseif arplatch==1 then
      params:set((k-1).."arp",1)
      params:set((k-1).."latch",0)
      params:set((k-1).."mute_non_arp",0)
    elseif arplatch==2 then
      params:set((k-1).."arp",1)
      params:set((k-1).."latch",1)
      params:set((k-1).."mute_non_arp",0)
    else
      params:set((k-1).."arp",1)
      params:set((k-1).."latch",1)
      params:set((k-1).."mute_non_arp",1)
    end
  elseif k>1 and params:get((k-1).."record")==1 then
    mg.voices[k-1].record_step_adj=util.clamp(mg.voices[k-1].record_step_adj+sign(d),-1*mg.voices[k-1].record_step,0)
    print("mg.voices[k-1].record_step_adj",mg.voices[k-1].record_step_adj)
  end
end

function key(k,z)
  if k==1 then
    shift=z==1
  elseif shift and z==1 then
    params:delta((k-1).."record")
    params:set((k-1).."play",0)
  elseif params:get((k-1).."record")==1 and z==1 then
    mg:record_add_rest_or_legato(k-1)
  elseif z==1 then -- stop/start
    params:delta((k-1).."play")
    params:set((k-1).."record",0)
  end
end


function redraw()
  screen.clear()
  screen.level(1)
  if shift then
    screen.level(15)
  end
  screen.move(64,1)
  screen.line(64,64)
  screen.stroke()
  screen.move(65,1)
  screen.line(65,64)
  screen.stroke()
  screen.level(15)
  for i=1,2 do
    screen.font_size(8)

    if params:get(i.."record")==1 then
      screen.move(26+72*(i-1),10)
      screen.text_center(mg:get_cluster(i))
    else
      screen.move(26+72*(i-1),10)
      screen.text_center(mg.voices[i].current_note)
    end
    screen.move(30+72*(i-1),54)
    if params:get(i.."play")==1 then
      screen.text_center("playing")
    elseif params:get(i.."record")==1 then
      screen.text_center("recording")
    end
    screen.move(30+72*(i-1),63)
    if params:get(i.."arp")==1 and params:get(i.."latch")==1 and params:get(i.."mute_non_arp")==1 then
      screen.text_center("arp+latch only")
    elseif params:get(i.."arp")==1 and params:get(i.."latch")==1 then
      screen.text_center("arp+latch")
    elseif params:get(i.."arp")==1 then
      screen.text_center("arp")
    end
    screen.move(28+72*(i-1),46)
    screen.font_size(48)
    if params:get(i.."record")==1 then
      screen.text_center(mg.voices[i].record_step+mg.voices[i].record_step_adj+1)
    else
      screen.text_center(mg.voices[i].play_step)
    end
  end
  screen.update()
end

function rerun()
  norns.script.load(norns.state.script)
end

function sign(x)
  if x>0 then
    return 1
  elseif x<0 then
    return-1
  else
    return 0
  end
end


