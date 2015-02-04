local overfull = 1073741820
local inf_bad = 10000
local eject_penalty = -inf_bad
local deplorable = 100000   --  worse than inifinitely bad!

local tcpb = {}

--! trim leading and trailing Vg from two column material first

-- Look best places to break oq into two columns.
-- Two column material starts at oq index 'left'.
-- Return starting index of right column, limit of right column, penalty.
-- Penalty will be ovefull if there is no way to do this.
function tcpb.findBestTwoColBreak(oq, left, targetHeight)
  assert(left >= 1 and left <= #oq)
  print("bestTwoColBreak left="..left, "targetHeight="..targetHeight, 
              "("..#oq..")")
  for i=left,#oq do
    print(i, oq[i])
  end

  local penalty = overfull
  local _right, _penalty, _height, right, rightEnd

  for _right=left+1,#oq+1 do
    if _right == #oq+1 or oq[_right]:isVbox() then
      local _rightEnd, _penalty, _height = tcpb.findBestTwoColBreak2(
                                     oq, left, _right, targetHeight)
      if _height > targetHeight then break end
      if _penalty <= penalty then 
        right, rightEnd, penalty = _right, _rightEnd, _penalty
      end
    end
  end
  
  return right, rightEnd, penalty
end

-- warning! right may be as large as #oq+1
-- returns rightEnd, penalty, height
function tcpb.findBestTwoColBreak2(oq, left, right, targetHeight)
  print("   findBestTwoColBreak2 left="..left, "right="..right, 
                       "targetHeight="..targetHeight)
  local leftHeight = tcpb.columnHeight(oq, left, right)
  if leftHeight > targetHeight then return nil, nil, leftHeight end
  local leftPenalty = tcpb.columnPenalty(oq, right)

  local rightEnd, penalty = nil, overfull

  for _rightEnd=right,#oq+1 do
    if _rightEnd == #oq+1 or oq[_rightEnd]:isVbox() then
      local rightHeight = tcpb.columnHeight(oq, right, _rightEnd)
      if rightHeight > leftHeight then break end
      local rightPenalty = tcpb.columnPenalty(oq, _rightEnd)

      local pageBottomGap = targetHeight - leftHeight
      local interColumnGap = leftHeight - rightHeight
      local _penalty = tcpb.calculatePenalty(leftPenalty, rightPenalty,    
                         pageBottomGap, interColumnGap)
      if _penalty <= penalty then 
        rightEnd, penalty = _rightEnd, _penalty 
      end 
    end
  end

  print("   *** rightEnd="..rightEnd, "penalty="..penalty, 
                            "leftHeight="..leftHeight)
  return rightEnd, penalty, leftHeight
end

function tcpb.calculatePenalty(leftPenalty, rightPenalty, pageBottomGap, interColumnGap)
  local penalty
  if leftPenalty > 100 or rightPenalty > 100 then 
    penalty = overfull 
  else
    penalty = pageBottomGap.length + 2*interColumnGap.length
  end

  print("      penalty="..penalty, 
    "    leftPenalty="..leftPenalty, "rightPenalty="..rightPenalty, 
    "pageBottomGap="..pageBottomGap, "interColumnGap="..interColumnGap)
  return penalty 
end

function tcpb.columnHeight(oq, first, last)
  local h = SILE.length.new({})

  local i
  for i=first,last do
    h = h + oq[i].height + oq[i].depth
  end

  print("      ***columnHeight="..h)
  return h
end

-- return height, penalty
function tcpb.columnPenalty(oq, last)
  local p = 0
  last = last+1
  while last <= #oq and oq[last]:isVglue() do last = last+1 end
  if last <= #oq and oq[last]:isPenalty() then p = oq[last].penalty end

  print("      ***penalty="..p)
  return p
end

return tcpb
