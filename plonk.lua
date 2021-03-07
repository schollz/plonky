-- plonk v0.0.0
-- 8 strings with 5th tuning
--


local plonk=include("plonk/lib/plonk")



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
  if k>=2 and z==1 then 
    mg:record_add_rest_or_legato(k-1)
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
      screen.move(12+68*(i-1),54)
      screen.text("recording")
    else
      screen.move(1+64*(i-1),10)
      screen.text(params:get(i.."current_note"))
    end
    screen.move(28+68*(i-1),46)
    screen.font_size(48)
    screen.text_center(mg.voices[i].record_step)
  end
  screen.update()
end

function rerun()
  norns.script.load(norns.state.script)
end
