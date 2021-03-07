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

end


function redraw()
  screen.clear()
  screen.level(15)
  for i=1,2 do
    screen.move(1+64*(i-1),10)
    screen.font_size(8)
    screen.text(params:get(i.."current_note"))
    screen.move(28+64*(i-1),46)
    screen.font_size(48)
    screen.text_center("1")
  end
  screen.update()
end

function rerun()
  norns.script.load(norns.state.script)
end
