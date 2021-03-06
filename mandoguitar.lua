-- mandoguitar v0.0.0
-- 8 strings with 5th tuning
--


local mandoguitar=include("mandoguitar/lib/mandoguitar")



function init()
  mg=mandoguitar:new({grid_on=true,toggleable=true})
end



function enc(k,d)

end

function key(k,z)

end


function redraw()
  screen.clear()

  screen.update()
end

function rerun()
  norns.script.load(norns.state.script)
end
