-- plonk v0.0.0
-- 8 strings with 5th tuning
--


local plonk=include("plonk/lib/plonk")
local shift=false
local arplatch=0

function init()
  mg=plonk:new({grid_on=true,toggleable=true})
  clock.run(function()
    while true do
      clock.sleep(1/10) -- refresh
      redraw()
    end
  end) -- start the grid redraw clock

end



function enc(k,d)
  if k>1 and params:get((k-1).."record")==0 then
    -- toggle arp/latch
    d=sign(d)
    arplatch=util.clamp(arplatch+d,0,2)
    if arplatch==0 then
      params:set((k-1).."arp",0)
      params:set((k-1).."latch",0)
    elseif arplatch==1 then
      params:set((k-1).."arp",1)
      params:set((k-1).."latch",0)
    else
      params:set((k-1).."arp",1)
      params:set((k-1).."latch",1)
    end
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
      screen.text_center(params:get(i.."current_note"))
    end
    screen.move(30+72*(i-1),54)
    if params:get(i.."play")==1 then
      screen.text_center("playing")
    elseif params:get(i.."record")==1 then
      screen.text_center("recording")
    end
    screen.move(30+72*(i-1),63)
    if params:get(i.."arp")==1 and params:get(i.."latch")==1 then
      screen.text_center("arp+latch")
    elseif params:get(i.."arp")==1 then
      screen.text_center("arp")
    end
    screen.move(28+72*(i-1),46)
    screen.font_size(48)
    if params:get(i.."record")==1 then
      screen.text_center(mg.voices[i].record_step)
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


