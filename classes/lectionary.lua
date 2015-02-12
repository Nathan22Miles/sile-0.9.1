
-- change lectionary_styles to .sil
-- import tcpb

-- microformats
-- process usx to input form, test for year B
--     support <eject/>
-- page headers
-- add headings to year C, test

-- table of contents
-- get lectionary test data
-- port to windows

-- SILE.debugFlags["break"] = true
--SILE.debugFlags.oyv = true
--SILE.debugFlags.oy = true
--SILE.debugFlags.dump = true

local plain = SILE.require("classes/plain");
local twocol = std.tree.clone(plain);
twocol.id = "twocol"

local tcpb = SILE.require("core/twocolpagebuilder")

twocol:loadPackage("masters")

twocol:defineMaster({ id = "right", firstContentFrame = "content", frames = {
  content = {
    left = "18%", 
    right = "90%", 
    top = "10%", 
    bottom = "top(footnotes)" 
  },
  runningHead = {
    left = "left(content)", 
    right = "right(content)", 
    top = "top(content) - 5%", 
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

function twocol:newPage()
  twocol:switchPage()
  -- print("newPage oddPage="..twocol:oddPage())
  return plain.newPage(self)
end

SILE.scratch.headers = {}
SILE.scratch.headers.newHeader = false
SILE.scratch.headers.pageno = 0

SILE.registerCommand("h", 
  function(options, content)
    SILE.scratch.headers.top = content
    SILE.scratch.headers.newHeader = true
  end, "Text to appear on the top of the left page");

-- page 1, no pageno
-- page 1, shifted left
-- page 3, bold pageno

function twocol:endPage()
  assert(SILE.scratch.headers.top)

  local frame = SILE.getFrame("runningHead")
  SILE.scratch.headers.pageno = SILE.scratch.headers.pageno + 1
  io.write("["..SILE.scratch.headers.pageno.."] ")

  if (twocol:oddPage() and SILE.scratch.headers.top) then
    SILE.typesetNaturally(frame, 
      function()
        -- hss, header, hss, pageno
        print("endPage oddPage="..twocol:oddPage())
        SILE.settings.set("current.parindent", SILE.nodefactory.zeroGlue)
        SILE.settings.set("typesetter.parfillskip", SILE.nodefactory.zeroGlue)
        SILE.call("hss")
        SILE.Commands["hfont"]({}, function()
          if not SILE.scratch.headers.newHeader then
            SILE.process(SILE.scratch.headers.top)
          end
        end)
        SILE.call("hss")
        SILE.Commands["bodyfont"]({}, function()
          SILE.typesetter:typeset(SILE.scratch.headers.pageno.."")
        end)
      end)
  elseif (not(twocol:oddPage()) and SILE.scratch.headers.top) then
    SILE.typesetNaturally(frame, 
      function()
        -- pageno, hss, header, hss
        print("endPage oddPage="..twocol:oddPage())
        SILE.settings.set("current.parindent", SILE.nodefactory.zeroGlue)
        SILE.settings.set("typesetter.parfillskip", SILE.nodefactory.zeroGlue)
        SILE.Commands["bodyfont"]({}, function()
          if not SILE.scratch.headers.newHeader then
            SILE.typesetter:typeset(SILE.scratch.headers.pageno.."")
          end
        end)
        SILE.call("hss")
        SILE.Commands["hfont"]({}, function()
          if not SILE.scratch.headers.newHeader then
            SILE.process(SILE.scratch.headers.top)
          end
        end)
        SILE.call("hss")
      end)
  end

  SILE.scratch.headers.newHeader = false

  --return plain.endPage(twocol);
end;

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

-- in order to not have extra space between paragraphs, make
-- font size + parskip = baselineskip
SILE.settings.set("document.parskip", SILE.nodefactory.newVglue("2pt"))
SILE.settings.set("document.baselineskip", SILE.nodefactory.newVglue("14pt"))

SILE.registerCommand("lineskip", function ( options, content )
    SILE.typesetter:leaveHmode();    
    SILE.typesetter:pushVglue(SILE.settings.get("document.baselineskip"))
  end, "Skip vertically by a line")

SILE.registerCommand("twocol", twocol_func, 
  "Temporarily switch to two balanced columns")

-- If we are near the end of a page this is a good place to break
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
  end, "good place to break")

function typesetter:init()
  self.left = 0
  self.frame = SILE.frames["content"]
  local ret = SILE.defaultTypesetter.init(self, self.frame)
  self.gapWidth = .05 * self.frame:width()
  return ret
end

function typesetter:startTwoCol()
  SILE.typesetter:leaveHmode()
  self.columnWidth = (self.frame:width() - self.gapWidth)  / 2
  SILE.settings.set("typesetter.breakwidth", SILE.length.new({ length = self.columnWidth }))

  local oq = self.state.outputQueue
  self.left = #oq + 1
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

  -- make 2col material start at first non-zero height vbox
  while self.left <= #oq do
    local box = oq[self.left]
    if box:isVbox() and box.height and box.height.length > 0 then break end
    self.left = self.left+1
  end
  if self.left > #oq then 
    SU.debug("columns", "   pageBuilder RETURN empty oq / false")
    self:endTwoCol()
    return false 
  end
  SU.debug("columns", "pageBuilder left="..self.left..", #oq="..#oq)

  local currentHeight = typesetter:totalHeight(1, self.left)
  local targetHeight = SILE.length.new({ length = self.frame:height() }) 
  targetHeight = targetHeight - currentHeight

  local p
  self.right, self.rightEnd, p = tcpb.findBestTwoColBreak(
         oq, self.left, targetHeight)

  if self.right then 
    assert(self.right > self.left)
    assert(self.rightEnd)
    assert(self.rightEnd >= self.right)
    assert(self.rightEnd <= #oq+1)
  end
  
  -- if can't fit any two column content on page then
  -- output all the one column content and eject
  if not self.right then
    assert(self.left > 1)
    self:outputLinesToPage2(1, self.left)  
    self.left = 1
    SU.debug("columns", 
       "   pageBuilder RETURN can't fit 2col material on page / true")
    return true
  end

  -- gather all the two column material between [self.left,self.rightEnd) that
  -- will fit on current page and place it in a single box at self.left
  typesetter:createTwoColVbox()
  self.rightEnd = self.left + 1

  -- if we have processed all the two column material then
  -- exit two column mode but do not output page because more
  -- material may still fit.
  if self.rightEnd == #oq+1 then 
    SU.debug("columns", 
       "   pageBuilder RETURN end 2c, page not full / false")
    self:endTwoCol()
    return false 
  end

  -- page is full, output it.
  -- stay in two col mode to output the rest
  local totalHeight = typesetter:totalHeight(1, self.rightEnd)
  local glues, gTotal = self:accumulateGlues(1, self.rightEnd)
  self:adjustGlues(targetHeight, totalHeight, glues, gTotal)
  self:outputLinesToPage2(1, self.rightEnd);
  
  self.left = 1
  SU.debug("columns", 
     "pageBuilder RETURN produced 2c page, more 2c material to process / true")
  return true
end

function typesetter:createTwoColVbox()
  local oq = self.state.outputQueue

  local vbox = SILE.nodefactory.newVbox({})
  vbox.outputYourself = twoColBoxOutputYourself

  while self.rightEnd > self.right and isDiscardable(oq[self.rightEnd-1]) do
    self.rightEnd = self.rightEnd - 1
  end
  vbox.rightCol = typesetter:extract(self.right, self.rightEnd)
  typesetter:removeDiscardable(vbox.rightCol)
  --typesetter:dump("rightCol", vbox.rightCol)

  while self.left <= #oq and isDiscardable(oq[self.left]) do 
    self.left = self.left + 1 
  end
  vbox.leftCol = typesetter:extract(self.left, self.right)
  typesetter:removeDiscardable(vbox.leftCol)
  --typesetter:dump("rightCol", vbox.leftCol)

  vbox.height = 0
  vbox.depth = tcpb.columnHeight(vbox.leftCol, 1, #vbox.leftCol)
  vbox.depth.stretch = 0
  vbox.depth.shrink = 0

  table.insert(oq, self.left, vbox)
end

function typesetter:extract(first, last)
  local oq = self.state.outputQueue
  local col, i = {}, nil
  for i=first,last-1 do
    col[#col+1] = oq[first]
    -- if col[#col]:isVglue() then col[#col]:setGlue(0) end
    table.remove(oq, first)
  end
  return col
end

function typesetter:removeDiscardable(col)
  while #col > 0 and isDiscardable(col[1]) do table.remove(col, 1) end
  while #col > 0 and isDiscardable(col[#col]) do table.remove(col, #col) end
end

function isDiscardable(box) return box:isPenalty() or box:isVglue() end

function twoColBoxOutputYourself(vbox, typesetter, line)
  local y0 = typesetter.frame.state.cursorY
  SU.debug("oyv", "y0="..y0)

  -- line up right column baseline with left column baseline
  typesetter.frame:moveY(vbox.leftCol[1].height.length)
  if #vbox.rightCol > 0 then
    typesetter.frame:moveY(-vbox.rightCol[1].height.length)
  end

  local horizOffset = typesetter.columnWidth + typesetter.gapWidth
  columnOutputYourself(vbox.rightCol, typesetter, horizOffset, line, "right")
  
  typesetter.frame.state.cursorY = y0
  columnOutputYourself(vbox.leftCol, typesetter, 0, line, "left")
end  

-- output one column of a custom two column vbox
function columnOutputYourself(col, typesetter, horizOffset, line, side)
  SU.debug("oyv", "output "..side.." column")
  local i
  for i=1,#col do
    typesetter.frame:newLine()
    typesetter.frame:moveX(horizOffset)
    local box = col[i]
    box:outputYourself(typesetter, box)
  end
end  

function typesetter:dump(heading, oq)
  if SILE.debugFlags["dump"] then
    print(heading)
    for i=1,#oq do
      print(i, oq[i])
    end
    print()
  end
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