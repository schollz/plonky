-- plonk v0.0.0
-- 8 strings with 5th tuning
--


local plonk=include("plonk/lib/plonk")
local shift=false


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
  screen.level(15)
  for i=1,2 do
    screen.font_size(8)

    if params:get(i.."record")==1 then
      screen.move(1+64*(i-1),10)
      screen.text(mg:get_cluster(i))
    else
      screen.move(1+64*(i-1),10)
      screen.text(params:get(i.."current_note"))
    end
    screen.move(12+68*(i-1),54)
    if params:get(i.."play")==1 then
      screen.text("playing")
    elseif params:get(i.."record")==1 then
      screen.text("recording")
    end
    screen.move(28+68*(i-1),46)
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
