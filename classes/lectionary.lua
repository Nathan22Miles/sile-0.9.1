
local plain = SILE.require("classes/plain");
local twocol = std.tree.clone(plain);
local tcpb = SILE.require("core/twocolpagebuilder")

SILE.require("packages/counters");
SILE.scratch.counters.folio = { value = 1, display = "arabic" };
--SILE.scratch.twocol = {}

local typesetter = SILE.defaultTypesetter {};
SILE.typesetter = typesetter

local function twocol_func(options, content)
  SU.debug("typesetter", "   start twocols")
  typesetter:startTwoCol()
  SILE.process(content)
  typesetter:leaveHmode()
  typesetter.allTwoColMaterialProcessed = true
  while typesetter:pageBuilder() do
  end
  typesetter:endTwoCol()
end

SILE.registerCommand("twocol", twocol_func, "Typeset content two balanced columns")

function typesetter:init()
  self.frame = SILE.frames["a"]
  local ret = SILE.defaultTypesetter.init(self, self.frame)
  self.gapWidth = .03 * self.frame:width()
  return ret
end

function typesetter:startTwoCol()
  local width = (self.frame:width() - self.gapWidth)  / 2
  SILE.settings.set("typesetter.breakwidth", SILE.length.new({ length = width }))
  self.left = #self.state.outputQueue + 1
  self.allTwoColMaterialProcessed = false
end

function typesetter:endTwoCol()
  SILE.settings.set("typesetter.breakwidth", SILE.length.new({ length = self.frame:width() }))
  self.left = 0
end

function typesetter:pageBuilder(independent)
  if self.left == 0 then
    return SILE.defaultTypesetter(self, indenpendent)
  end

  -- process all two column material before attempting to build page
  if not self.allTwoColMaterialProcessed then return false end

  local oq = self.state.outputQueue
  local targetHeight = SILE.length.new({ length = self.frame:height() }) -- XXX Floats
  targetHeight = targetHeight - self:totalHeight(1, self.left)

  local p, right, rightEnd = tcpb.findBestTwoColBreak(oq, self.left, targetHeight)

  -- if can't put any two col content on page then
  if not right then
    self:outputLinesToPage2(1, self.left)  -- output one column content, remove from outputQueue
    self.left = 1
    return true -- return true to try again on next page
  end

  local vbox = self:buildTwoColVbox(self.left, right, rightEnd)
  self:removeFromOutputQueue(self.left, rightEnd)
  table.insert(oq, self.left, vbox)

  -- if there is nothing more in the output queue perhaps more will fit on page, don't output it yet
  -- but we are still in two column mode starting at right after the two column vbox we just inserted
  if tcpb.remainingLinesPenalty(oq, self.left+1) == 0 then
    self:endTwoCol()
    return false
  end

  -- page is full, stay in two col mode to output the rest
  local totalHeight = self:totalHeight(1, self.left+1)
  local glues, gTotal = self:accumulateGlues(1, self.left+1)
  self:adjustGlues(targetHeight, totalHeight, glues, gTotal)
  self:outputLinesToPage2(1, self.left+1);

  self.left = self.left + 1

  return true
end

function typesetter:outputLinesToPage2(first, last)
  SU.debug("pagebuilder", "OUTPUTTING frame "..self.frame.id);
  local oq = self.state.outputQueue
  local i
  for i = first,last-1 do 
    local line = oq[i]
    print("output "..line)
    if not self.frame.state.totals.pastTop and not (line:isVglue() or line:isPenalty()) then
      self.frame.state.totals.pastTop = true
    end
    if self.frame.state.totals.pastTop then
      line:outputYourself(self, line)
    end
  end

  self:removeFromOutputQueue(first, last)
end

function typesetter:removeFromOutputQueue(first, last)
  local i
  for i=1,last-first do
    table.remove(self.state.outputQueue, first)
  end
end

-- look at page, find all glues, return them and their total height
function typesetter:accumulateGlues(first, last)
  local glues = {}
  local totalGlueHeight = SILE.length.new()
  local oq = self.state.outputQueue

  local i
  for i=first,last-1 do
    if oq[i]:isVglue() then 
      table.insert(glues,oq[i]);
      totalGlueHeight = totalGlueHeight + oq[i].height
    end
  end
  return glues, totalGlueHeight
end

-- stretch vertical glues to match targetHeight
function typesetter:adjustGlues(targetHeight, totalHeight, glues, gTotal)
  local adjustment = (targetHeight - totalHeight)
  if type(adjustment) == "table" then adjustment = adjustment.length end

  if (adjustment > gTotal.stretch) then adjustment = gTotal.stretch end
  if (adjustment / gTotal.stretch > 0) then 
    for i,g in pairs(glues) do
      g:setGlue(adjustment * g.height.stretch / gTotal.stretch)
    end
  end

  SU.debug("pagebuilder", "Glues for self page adjusted by "..(adjustment/gTotal.stretch) )
end

-- build a vbox containing the left column, gap, right column
function typesetter:buildTwoColVbox(left, right, rightEnd)
  local oq = self.state.outputQueue
  local leftCol = tcpb.collateVboxes(oq, left, right)
  local rightCol = tcpb.collateVboxes(oq, right, rightEnd)
  local gap = SILE.nodefactory.newGlue({width = SILE.length.new({ length = self.gapWidth })})

  local vbox = SILE.nodefactory.newVbox({
    width = self.frame:width(),
    depth = 0,
    value = {leftCol, gap, rightCol},
    outputYourself = function (self, typesetter, line)
      local i
      for i = 1, #(self.value) do 
        local node = self.value[i]
        node:outputYourself(typesetter, line)
      end
    end
  })
  vbox.height = leftCol.height

  return vbox
end

-- total up the height of the node list
function typesetter:totalHeight(first, last)
  local oq = self.state.outputQueue
  local totalHeight = 0
  local i
  for i=first,last-1 do
    totalHeight = totalHeight + oq[i].height + oq[i].depth
  end
  return totalHeight
end

return twocol