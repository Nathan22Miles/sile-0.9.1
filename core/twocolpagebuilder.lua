local overfull = 1073741823 
local inf_bad = 10000
local eject_penalty = -inf_bad
local deplorable = 100000   --  worse than inifinitely bad!

local unusedLinePenalty = 100

local tcpb = {}

-- Look for the best place to break oq.
-- Start at index 'first' in oq.
-- Value returned must be <= limit.
-- Total boxes selected must not have more than targetHeight total.
-- Return the index in oq of the first box AFTER the break and
-- the penalty for breaking at this point.
-- Return nil, nil if not possisible break found.
function tcpb.findBestBreak(oq, first, limit, targetHeight)
  --print ("findBestBreak ", #oq, first, limit, targetHeight)
  local totalHeight = 0
  local bestBreak = first
  local leastCost = inf_bad

  local i
  for i = first,limit-1 do 
    local vbox = oq[i]
    totalHeight = totalHeight + tcpb.boxHeight(vbox)
    local remainingHeight = (targetHeight - totalHeight).length
    if remainingHeight < 0 then break end

    local p = tcpb.breakPenalty(oq, i)
    if p <= eject_penalty then return p, i end
    --print("totalHeight/remainingHeight/p ", totalHeight, remainingHeight, p)
    if p < inf_bad then
      local c = p + remainingHeight * remainingHeight * remainingHeight
      if c < leastCost then
        --print("bestBreak", bestBreak)
        leastCost = c
        bestBreak = i
      end
    end
  end

  return leastCost, bestBreak
end

function tcpb.breakPenalty(oq, i)
  local vbox = oq[i]
  if vbox:isPenalty() then return vbox.penalty end
  if vbox:isVglue() and i > 1 and not oq[i-1]:isDiscardable() then return 0 end
  return deplorable
end

-- Look best places to break oq into two columns.
-- Two column material starts at oq index 'left'.
-- Return nil, nil, nil if no way
-- Return starting index of right column, limit of right column, penalty.
function tcpb.findBestTwoColBreak(oq, left, targetHeight)
  --print("#oq", #oq)
  local bestRight = nil     -- proposed start index for right column.
  local bestRightEnd = nil  -- proposed index for first box not in right column
  local bestPenalty = overfull  -- penalty for this break

  local right
  for right=left+1,#oq do
    local penalty, rightEnd = tcpb.twoColBreakPenalty(oq, left, right, targetHeight)
    if penalty == overfull then 
      break 
    end
    if penalty < bestPenalty then
      --print("newBestTwoColBreak", penalty, left, right, rightEnd)
      bestPenalty, bestRight, bestRightEnd = penalty, right, rightEnd
    end
  end

  print("bestTwoColBreak", bestPenalty, left, bestRight, bestRightEnd)
  return bestPenalty, bestRight, bestRightEnd
end

-- Given the start position of left and right column, calculate the best rightEnd.
-- Return total penalty, rightEnd
function tcpb.twoColBreakPenalty(oq, left, right, remainingHeight)
  local height = tcpb.columnHeight(oq, left, right)
  if height > remainingHeight then 
    return overfull, nil 
  end

  local leftPenalty = tcpb.breakPenalty(oq, right)
  local rightPenalty, rightEnd = tcpb.findBestBreak(oq, right, #oq+1, height)
  local extraPenalty = tcpb.remainingLinesPenalty(oq, rightEnd)
  local penalty = leftPenalty + rightPenalty + extraPenalty
  print("twoColBreakPenalty", left, right, rightEnd, penalty, leftPenalty, rightPenalty, extraPenalty)
  return penalty, rightEnd
end

function tcpb.remainingLinesPenalty(oq, first)
  local remainingLines = 0
  for i=first,#oq do
    if oq[i]:isVbox() then remainingLines = remainingLines + 1 end
  end

  --if remainingLines > 0 and remainingLines < 5 then return inf_bad end
  return unusedLinePenalty * remainingLines
end

function tcpb.columnHeight(oq, first, last)
  local h = SILE.length.new({})
  local i
  for i=first,last do
    h = h + oq[i].height + oq[i].depth
  end
  return h
end

function tcpb.boxHeight(vbox)
  SU.debug("tcpb", "Dealing with VBox " .. vbox)
  --print("Dealing with VBox " .. vbox)
  if (vbox:isVbox()) then
    return vbox.height + vbox.depth
  elseif vbox:isVglue() then
    return vbox.height.length
  end
  return 0
end 

function tcpb.collateVboxes(oq, first, last)
  local i
  local output = SILE.nodefactory.newVbox({nodes = {} })
  local h = SILE.length.new({})
  for i=first,last-1 do
    table.insert(output.nodes, oq[i])
    h = h + oq[i].height + oq[i].depth
  end
  output.ratio = 1
  output.height = h
  output.depth = 0
  return output
end

SILE.pagebuilder = tcpb

return tcpb
