local overfull = 1073741823
local inf_bad = 10000
local eject_penalty = -inf_bad
local deplorable = 100000   --  worse than inifinitely bad!

local unusedLinePenalty = 100

local tcpb = {}

-- Look for the best place to break oq. Start at first.
-- If found, return index of best break and its cost.
function tcpb.findBestBreak(oq, first, last, targetHeight, usage)
  SU.debug("pagebuilder", "findBestBreak " .. usage .. " " .. first .. "/" .. last .. "/" .. targetHeight)
  local totalHeight = 0
  local bestBreak = nil
  local leastCost = inf_bad
  local p = 0

  local i
  for i = first,last do 
    -- do I still need this???
    if i == last then
      SU.debug("pagebuilder", "    bestBreak(used all) " .. bestBreak .. "   " .. leastCost)
      return bestBreak, leastCost
    end
    
    local vbox = oq[i]
    p = vbox:isPenalty() and vbox.penalty or 0
  
    totalHeight = totalHeight + tcpb.boxHeight(vbox)
    local remainingHeight = (targetHeight - totalHeight).length
    --SU.debug("pagebuilder", vbox .. "/remaining=" .. remainingHeight)
    
  
    local nonInfinitePenalty = vbox:isPenalty() and vbox.penalty < inf_bad
    local glueAfterNonDiscardableBox = vbox:isVglue() and i > 1 and not oq[i-1]:isDiscardable()
    if  nonInfinitePenalty or glueAfterNonDiscardableBox then
      local c = tcpb.calculateCost(remainingHeight, p)
      --SU.debug("pagebuilder ", "c " .. c)
      
      if c < leastCost then
        --SU.debug("pagebuilder", "leastCost " .. c)
        leastCost = c
        bestBreak = i
      end

      -- keep looking until we are overfull or see an eject
      if c == overfull or p <= eject_penalty then
        if not bestBreak then bestBreak = i-1 end
        
        SU.debug("pagebuilder", "    bestBreak " .. bestBreak .. "   " .. leastCost)
        return bestBreak, leastCost
      end
    end
  end

  SU.debug("pagebuilder", "    No page break here")
  return nil, nil
end

-- Look best places to break oq into two columns.
-- Return index of beginning of right column, last of right column, penalty for this break
-- Return nil, nil, nil if no way to break into two columns
function tcpb.findBestTwoColBreak(oq, left, targetHeight)
  SU.debug("pagebuilder", "findBestTwoColBreak left=" .. left .. "  targetHeight=" .. targetHeight)
  local right, rightLimit, cost, leftHeight, rightHeight, ignore

  local dimen = tcpb.columnHeight(oq, left, #oq+1).length / 2 -- calc half the height of two col material

  -- try to fit both columns on page
  while dimen <= targetHeight.length do
    right, cost = tcpb.findBestBreak(oq, left, #oq+1, dimen, "left col")
    if right then
      leftHeight = tcpb.columnHeight(oq, left, right)
      rightHeight = tcpb.columnHeight(oq, right, #oq+1)
      SU.debug("pagebuilder", "    searching "..dimen.."/"..right.."/"..leftHeight.."/"..rightHeight)

      -- if left col at least as tall as right col, we are done
      if leftHeight >= rightHeight then 
        rightLimit = #oq+1
        SU.debug("pagebuilder", "    fit on page "..left.."/"..right.."/"..rightLimit)
        return right, rightLimit, cost 
      end
    end
    dimen = dimen + 1
  end

  -- we can't fit everything on the page, fit as much as we can subject
  -- to the restriction that the right column is no longer than the left
  right, cost = tcpb.findBestBreak(oq, left, #oq+1, targetHeight, "full page left col")
  if not right then 
    SU.debug("pagebuilder", "failed to find left col break")
    return nil, nil, nil 
  end

  leftHeight = tcpb.columnHeight(oq, left, right)
  rightLimit, ignore = tcpb.findBestBreak(oq, right, #oq+1, leftHeight, "full page right col")
  if not right then 
    SU.debug("pagebuilder", "failed to find right col break")
    return nil, nil, nil 
  end

  SU.debug("pagebuilder", "    partial fit on page "..left.."/"..right.."/"..rightLimit)
  return right, rightLimit, cost
end

function tcpb.columnHeight(oq, first, last)
  local h = SILE.length.new({})
  local i
  for i=first,last-1 do
    h = h + oq[i].height + oq[i].depth
  end
  return h
end

function tcpb.calculateCost(remainingHeight, p)
  if remainingHeight < 0 then return overfull end
  local badness = remainingHeight * remainingHeight * remainingHeight

  if p <= eject_penalty then return p end
  if badness < inf_bad then return badness + p end
  return deplorable
end

function tcpb.boxHeight(vbox)
  SU.debug("tcpb", "Dealing with VBox " .. vbox)
  if (vbox:isVbox()) then
    return vbox.height + vbox.depth
  elseif vbox:isVglue() then
    return vbox.height.length
  end
  return 0
end 

function tcpb.collateVboxes(oq, first, last)
  local output = SILE.nodefactory.newVbox({nodes = {} })
  local h = SILE.length.new({})

  local i
  for i=first,last-1 do
    table.insert(output.nodes, oq[i])
    h = h + oq[i].height + oq[i].depth
  end
  output.ratio = 1
  output.height = h
  output.depth = 0
  return output
end

--SILE.pagebuilder = tcpb

return tcpb
