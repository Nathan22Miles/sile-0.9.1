local overfull = 1073741820
local inf_bad = 10000
local eject_penalty = -inf_bad
local deplorable = 100000   --  worse than inifinitely bad!

local tcpb = {}

--! is something special needed for eject penalty?

-- Look at all the material left..#oq.
-- Find 'best' place into two columns that fit on current page.
-- Return right, rightEnd, penalty.
-- Penalty will be ovefull if there is no way to fit anything on page.
function tcpb.findBestTwoColBreak(oq, left, targetHeight)
  assert(left >= 1 and left <= #oq)
  print("findBestTwoColBreak left="..left, "targetHeight="..targetHeight, 
              "("..#oq..")")

  local right, rightEnd, penalty = nil, nil, overfull  -- outputs
  local _right, _rightEnd, _penalty, _height 

  for _right=left+1,#oq+1 do
    if _right == #oq+1 or oq[_right]:isVbox() then
      local _rightEnd, _penalty, _height = tcpb.findBestTwoColBreak2(
                                     oq, left, _right, targetHeight)
      if _height > targetHeight then break end
      if _rightEnd and _penalty <= penalty then 
        right, rightEnd, penalty = _right, _rightEnd, _penalty
      end
    end
  end
  
  print("   ****** right="..right, "rightEnd="..rightEnd, "penalty="..penalty)
  return right, rightEnd, penalty
end

-- warning! right may be as large as #oq+1
-- returns rightEnd, penalty, height
function tcpb.findBestTwoColBreak2(oq, left, right, targetHeight)
  print("   findBestTwoColBreak2 left="..left, "right="..right, 
                       "targetHeight="..targetHeight)
  local rightEnd, penalty, leftHeight = nil, overfull, nil   -- outputs

  leftHeight = tcpb.columnHeight(oq, left, right)
  if leftHeight > targetHeight then return rightEnd, penalty, leftHeight end
  local leftPenalty = tcpb.columnPenalty(oq, right)

  for _rightEnd=right,#oq+1 do
    if _rightEnd == #oq+1 or oq[_rightEnd]:isVbox() then
      local rightHeight = tcpb.columnHeight(oq, right, _rightEnd)
      if rightHeight > leftHeight then 
        print("         rightHeight > leftHeight")
        break 
      end

      local rightPenalty = tcpb.columnPenalty(oq, _rightEnd)
      local pageBottomGap = targetHeight - leftHeight
      local interColumnGap = leftHeight - rightHeight
      local _penalty = tcpb.calculatePenalty(leftPenalty, rightPenalty,    
                         pageBottomGap, interColumnGap)
      print("         ***", _penalty, right.."/".._rightEnd)
      if _rightEnd and _penalty <= penalty then 
        rightEnd, penalty = _rightEnd, _penalty 
      end 
    end
  end

  print("      ***", penalty, right.."/"..rightEnd, "h="..leftHeight)
  return rightEnd, penalty, leftHeight
end

-- return penalty
function tcpb.calculatePenalty(leftPenalty, rightPenalty, pageBottomGap, interColumnGap)
  local penalty
  if leftPenalty > 100 or rightPenalty > 100 then 
    penalty = overfull 
  else
    penalty = pageBottomGap.length + interColumnGap.length
  end

  --print("      *** penalty="..penalty, leftPenalty, rightPenalty, pageBottomGap, interColumnGap)
  return penalty 
end

function tcpb.columnHeight(oq, first, last)
  local h = SILE.length.new({})

  local i
  for i=first,last-1 do
    assert(i <= #oq, first.."/"..last)
    assert(oq[i])
    h = h + oq[i].height + oq[i].depth
  end

  --print("      *** columnHeight="..h)
  return h
end

-- return height, penalty
function tcpb.columnPenalty(oq, last)
  local p = 0
  last = last-1
  while last >= 1 and oq[last]:isVglue() do last = last-1 end
  if last >= 1 and oq[last]:isPenalty() then p = oq[last].penalty end

  --print("      *** columnPenalty="..p)
  return p
end

return tcpb
