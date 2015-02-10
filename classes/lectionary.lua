-- page 1 
---- line spacing
---- hyphenation
---- going past bottom margin
-- microformats
-- keep together/dont start new section near bottom of page
-- move formats to an included file
-- process usx to input form, test for year B
--     support <eject/>
-- page headers
-- table of contents
-- add headings to year C, test


-- figure out what really needs done with parskip

-- get lectionary test data
-- port to windows

-- SILE.debugFlags.oy = true
-- SILE.debugFlags.twocol = true
-- SILE.debugFlags["lectionary"] = true
-- SILE.debugFlags.typesetter = true
-- SILE.debugFlags.outputLinesToPage2 = true
-- SILE.debugFlags["break"] = true

--SILE.debugFlags["lectionary+"] = true
--SILE.debugFlags.leading = true


-- print("twocol loaded")

local plain = SILE.require("classes/plain");
local twocol = std.tree.clone(plain);
twocol.id = "twocol"

local tcpb = SILE.require("core/twocolpagebuilder")

twocol:loadPackage("masters")

twocol:defineMaster({ id = "right", firstContentFrame = "content", frames = {
  content = {
    left = "10%", 
    right = "82%", 
    top = "10%", 
    bottom = "top(footnotes)" 
  },
  folio = {
    left = "left(content)", 
    right = "right(content)", 
    top = "bottom(footnotes)+3%",
    bottom = "bottom(footnotes)+5%" 
  },
  runningHead = {
    left = "left(content)", 
    right = "right(content)", 
    top = "top(content) - 7%", 
    bottom = "top(content)-2%" 
  },
  footnotes = { 
    left="left(content)", 
    right = "right(content)", 
    height = "0", 
    bottom="92%"}
}})

twocol:loadPackage("twoside", { oddPageMaster = "right", evenPageMaster = "left" });

twocol:mirrorMaster("right", "left")

twocol.pageTemplate = SILE.scratch.masters["right"]

-- see book.endPage for running headers code

function twocol:newPage()
  twocol:switchPage()
  return plain.newPage(self)
end

--function twocol:endPage()
--  print("twocol endPage")
--  plain:endPage()
--end

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
    typesetter:initNextFrame()
  end

  typesetter:endTwoCol()
end

SILE.settings.set("document.parskip", SILE.nodefactory.newVglue("2pt"))
SILE.settings.set("document.baselineskip", SILE.nodefactory.newVglue("14pt"))

SILE.registerCommand("lineskip", function ( options, content )
    SILE.typesetter:leaveHmode();    
    SILE.typesetter:pushVglue(SILE.settings.get("document.baselineskip"))
  end, "Skip vertically by a line")

SILE.registerCommand("twocol", twocol_func, "Typeset content two balanced columns")

local plus90 = SILE.nodefactory.newVglue(
  {height = SILE.length.new({length = 90})})
local minus90 = SILE.nodefactory.newVglue(
  {height = SILE.length.new({length = -90})})


SILE.registerCommand("gdbreak", function(o,c) 
  SILE.typesetter:leaveHmode()
  SILE.typesetter:pushPenalty({ flagged= 1, penalty= -500 })
  SILE.typesetter:pushVglue(plus90) 
  SILE.typesetter:pushPenalty({ flagged= 1, penalty= -500 })
  SILE.typesetter:pushVglue(minus90) 
  end, "good place to break even if we need some stretch first")


-- SILE.settings.set("linebreak.tolerance", 1000)

function typesetter:init()
  self.left = 0
  twocol:switchPage()    -- make page 1 be a right hand page
  self.frame = SILE.frames["content"]
  local ret = SILE.defaultTypesetter.init(self, self.frame)
  self.gapWidth = .05 * self.frame:width()
  return ret
end

function typesetter:startTwoCol()
  SILE.typesetter:leaveHmode()
  self.columnWidth = (self.frame:width() - self.gapWidth)  / 2
  SILE.settings.set("typesetter.breakwidth", SILE.length.new({ length = self.columnWidth }))
  self.left = #self.state.outputQueue + 1
  self.allTwoColMaterialProcessed = false
end

function typesetter:endTwoCol()
  SILE.settings.set("typesetter.breakwidth", SILE.length.new({ length = self.frame:width() }))
  self.left = 0
end

-- Output one page.
-- Return true if page is complete.
function typesetter:pageBuilder(independent)
  -- if not two column material present, use default typesetter
  if self.left == 0 then 
    return SILE.defaultTypesetter.pageBuilder(self, independent)
  end

  -- process all two column material before attempting to build page
  if not self.allTwoColMaterialProcessed then return false end

  local oq = self.state.outputQueue
  SU.debug("lectionary", "pageBuilder left="..self.left..", #oq="..#oq)

  -- remove all variability from 2col material
  for i=self.left,#oq do
    local box = oq[i]
    if box:isVglue() then
      box.height.shrink = 0
      box.height.stretch = 0
    end
  end

  typesetter:removeDiscardable(self.left)
  if #oq == 0 then 
    SU.debug("lectionary", "   pageBuilder RETURN empty oq / false")
    self:endTwoCol()
    return false 
  end

  local currentHeight = typesetter:totalHeight(1, self.left)
  local targetHeight = SILE.length.new({ length = self.frame:height() }) 
  targetHeight = targetHeight - currentHeight

  local right, rightEnd, p = tcpb.findBestTwoColBreak(
         oq, self.left, targetHeight)

  if right then
    assert(right > self.left) 
    assert(rightEnd) 
    assert(rightEnd >= right)
    assert(rightEnd <= #oq+1)
  end
  
  -- if can't fit any two column content on page then
  -- output all the one column content and eject
  if not right then
    assert(self.left > 1)
    self:outputLinesToPage2(1, self.left)  
    self.left = 1
    SU.debug("lectionary", 
       "   pageBuilder RETURN can't fit 2c material on page / true")
    return true
  end

  right, rightEnd = self:adjustRightColumn(self.left, right, rightEnd)

  -- if we have processed all the two column material then
  -- exit two column mode but do not output page because more
  -- material may still fit.
  if rightEnd == #oq+1 then 
    SU.debug("lectionary", 
       "   pageBuilder RETURN end 2c, page not full / false")
    self:endTwoCol()
    return false 
  end

  -- page is full, output it.
  -- stay in two col mode to output the rest
  local totalHeight = typesetter:totalHeight(1, rightEnd)
  local glues, gTotal = self:accumulateGlues(1, rightEnd)
  self:adjustGlues(targetHeight, totalHeight, glues, gTotal)
  self:outputLinesToPage2(1, rightEnd);
  
  self.left = 1
  SU.debug("lectionary", 
     "pageBuilder RETURN produced 2c page, more 2c material to process / true")
  return true
end

function typesetter:dumpOq()
  if SILE.debugFlags["lectionary+"] then
    local oq = self.state.outputQueue
    for i=1,#oq do
      print(i, oq[i])
    end
  end
end

function typesetter:adjustRightColumn(left, right, rightEnd)
  local oq = self.state.outputQueue
  SU.debug("lectionary+", 
    "   adjustRightColumn left="..left.. 
    ", right="..right.." ,rightEnd="..rightEnd.." ("..#oq..")")
  typesetter:dumpOq()

  local rightColumnOffset = self.columnWidth + self.gapWidth
  local offsetGlue = SILE.nodefactory.newGlue(
                 {width = SILE.length.new({ length = rightColumnOffset })})
  
  -- we need an empty hbox because leading glue is ignored
  local emptyHbox = SILE.nodefactory.newHbox(
    {height = 0, width = 0, depth = 0, value = {glyphString = nil} })

  -- shift right column right
  local i
  for i = right,rightEnd-1 do
    local box = oq[i]
    if box:isVbox() then
      table.insert(box.nodes, 1, offsetGlue)
      table.insert(box.nodes, 1, emptyHbox)
    end
  end

  local count = typesetter:removeDiscardableFromEnd(rightEnd)
  rightEnd = rightEnd - count
  if rightEnd < right then right = rightEnd end

  --print()
  --print("after remove from rightEnd right="..right..", rightEnd="..rightEnd)
  --typesetter:dumpOq()

  count = typesetter:removeDiscardableFromEnd(right)
  right = right - count
  rightEnd = rightEnd - count
 
  --print()
  --print("after remove from right right="..right..", rightEnd="..rightEnd)
  --typesetter:dumpOq()
 
  -- add negative glue to make right column start at same height as left column
  -- add positive glue to make right column as long as left column
  local leftColumnHeight = typesetter:totalHeight(left, right).length
  SU.debug("lectionary+", "leftColumnHeight="..leftColumnHeight)
  local rightColumnHeight = typesetter:totalHeight(right, rightEnd).length
  local negativeVglue = SILE.nodefactory.newVglue(
                 {height = SILE.length.new({ length = -leftColumnHeight })})
  local positiveVglue = SILE.nodefactory.newVglue(
                 {height = SILE.length.new({ length = leftColumnHeight-rightColumnHeight })})
  table.insert(oq, rightEnd, positiveVglue)
  table.insert(oq, right, negativeVglue)

  rightEnd = rightEnd+2

  SU.debug("lectionary+", 
    "      after adjustRightColumn right="..right..", rightEnd="..rightEnd)
  typesetter:dumpOq()
  return right, rightEnd
end

function typesetter:removeDiscardable(first)
  local oq = self.state.outputQueue
  local discarded = 0
  while first > 0 and first <= #oq and (oq[first]:isPenalty() or oq[first]:isVglue()) do
    table.remove(oq, first)
    discarded = discarded+1
  end

  return discarded
end

function typesetter:removeDiscardableFromEnd(last)
  local oq = self.state.outputQueue
  local discarded = 0
  last = last-1
  while last > 0 and last <= #oq and (oq[last]:isPenalty() or oq[last]:isVglue()) do
    table.remove(oq, last)
    discarded = discarded+1
  end

  return discarded
end

function typesetter:totalHeight(left, right)
  return tcpb.columnHeight(self.state.outputQueue, left, right)
end

-- first = first oq item to output
-- last = first oq item to not output
function typesetter:outputLinesToPage2(first, last)
  if last <= first then return end

  local oq = self.state.outputQueue

  assert(last > first)
  assert(last-1 <= #oq)

  if SILE.debugFlags["outputLinesToPage2"] then
    print("outputLinesToPage2")
    for i=first,last do
      print(i, oq[i])
    end
  end

  SU.debug("pagebuilder", "OUTPUTTING frame "..self.frame.id);

  local i
  for i = first,last-1 do 
    local line = oq[i]
    assert(line, "empty oq element at position "..i.." of "..#oq)
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

return twocol