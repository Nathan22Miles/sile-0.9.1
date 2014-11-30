-- self.state.nodes (horizontal)
-- self.state.outputQueue
-- self.frame

-- This is the default typesetter. You are, of course, welcome to create your own.

SILE.defaultTypesetter = std.object {
  -- Setup functions
  init = function(self, frame)
    self.stateQueue = {};
    self:initFrame(frame)
    self:initState();
    return self
  end,

  initState = function(self)
    self.state = {
      nodes = {},        -- horizontal mode
      outputQueue = {},  -- vertical mode 
      lastBadness = awful_bad,      
    };
    self:initline()
  end,

  initline = function (self)
    if (#self.state.nodes == 0) then
      table.insert(self.state.nodes, SILE.nodefactory.zeroHbox)
    end
  end,

  initFrame = function(self, frame)
    self.frame = frame
    self.frame:init()
  end,

  pushState = function(self)
    table.insert(self.stateQueue, self.state);
    self:initState();
  end,

  popState = function(self)
    self.state = table.remove(self.stateQueue)
    if not self.state then SU.error("Typesetter state queue empty") end
  end,
  
  -- we are in vertical mode iff there is nothing in the horizontal mode list
  vmode = function(self)
    return #self.state.nodes == 0
  end,

  -- dump contents of horizontal and vertical mode lists
  debugState = function(self)
    print("\n---\nI am in "..(self:vmode() and "vertical" or "horizontal").." mode")
    print("Recent contributions: ")
    for i = 1,#(self.state.nodes) do
      io.write(self.state.nodes[i].. " ")
    end
    print("\nVertical list: ")
    for i = 1,#(self.state.outputQueue) do
      print("  "..self.state.outputQueue[i])
    end
  end,

  -- -------------------------
  -- Boxy stuff
  -- -------------------------

  pushHbox = function (self, spec) 
    table.insert(self.state.nodes, SILE.nodefactory.newHbox(spec))
    end,

  pushGlue = function (self, spec) 
    return table.insert(self.state.nodes, SILE.nodefactory.newGlue(spec))
    end,
  
  pushPenalty = function (self, spec)
    return table.insert(self.state.nodes, SILE.nodefactory.newPenalty(spec))
    end,
  
  pushVbox = function (self, spec) 
    local v = SILE.nodefactory.newVbox(spec); table.insert(self.state.outputQueue,v)
    return v
    end,

  pushVglue = function (self, spec) 
    return table.insert(self.state.outputQueue, SILE.nodefactory.newVglue(spec))
    end,
  
  pushVpenalty = function (self, spec) 
    return table.insert(self.state.outputQueue, SILE.nodefactory.newPenalty(spec))
    end,

  -- -------------------------
  -- Actual typesetting functions
  -- -------------------------

  typeset = function (self, text)
    for t in SU.gtoke(text,SILE.settings.get("typesetter.parseppattern")) do
      if (t.separator) then 
        self:leaveHmode();
        SILE.documentState.documentClass.endPar(self)
      else self:setpar(t.string)
      end
    end
  end,

  -- Takes string, writes onto self.state.nodes
  setpar = function (self, t)
    t = string.gsub(t,"\n", " ");
    --t = string.gsub(t,"^%s+", "");
    if (#self.state.nodes == 0) then
      self:initline()
      SILE.documentState.documentClass.newPar(self)
    end
    for token in SU.gtoke(t, "-") do
      local t2= token.separator and token.separator or token.string
      local newNodes = SILE.shaper.shape(t2)
      for i=1,#newNodes do
          self.state.nodes[#(self.state.nodes)+1] = newNodes[i]
          -- there is a penalty for breaking a line at a hyphen
          if token.separator then
            self.state.nodes[#(self.state.nodes)+1] = SILE.nodefactory.newPenalty({ value = SILE.settings.get("linebreak.hyphenPenalty") })
          end
      end
    end
  end,

  boxUpNodes = function (self, nl)
    self:removeEndOfListPenalties(nl)

    self:pushGlue(SILE.settings.get("typesetter.parfillskip"));
    self:pushPenalty({ flagged= 1, penalty= -inf_bad });   -- a good place to break a page??

    local breakWidth = SILE.settings.get("typesetter.breakwidth") or self.frame:width()
    if (type(breakWidth) == "table") then breakWidth = breakWidth.length end

    -- Find best places to break into lines.
    -- Breaks look like {position = , width = }
    local breaks = SILE.linebreak:doBreak(nl, breakWidth);
    if (#breaks == 0) then
      SU.error("Couldn't break :(")
    end

    local lines = self:breakpointsToLines(breaks);

    local vboxes = {}
    local previousVbox = nil
    
    for index=1, #lines do
      local line = lines[index]
      local vbox = SILE.nodefactory.newVbox({ nodes = line.nodes, ratio = line.ratio });
        
      if index > 1 then
        vboxes[#vboxes+1] = self:leadingFor(vbox, previousVbox)
      end
    
      vboxes[#vboxes+1] = vbox
      previousVbox = vbox
      self:addWidowOrphanPenalty(#lines, index, vboxes)
    end
    
    return vboxes
  end,

  addWidowOrphanPenalty = function(self, len, index, vboxes)
    local pageBreakPenalty = 0
    if (len > 1 and index == 1) then
      pageBreakPenalty = SILE.settings.get("typesetter.widowpenalty")
    elseif (len > 1 and index == (len-1)) then
      pageBreakPenalty = SILE.settings.get("typesetter.orphanpenalty")
    end
  
    if pageBreakPenalty > 0 then
      vboxes[#vboxes+1] = SILE.nodefactory.newPenalty({ penalty = pageBreakPenalty})
    end
  end,

  -- Remove penalties from ends of list, glue from start only
  removeEndOfListPenalties = function (self, nl)
    while (#nl > 0 and (nl[#nl]:isPenalty() or nl[#nl]:isGlue())) do
     table.remove(nl);
    end
    while (#nl >0 and nl[1]:isPenalty()) do table.remove(nl,1) end

  -- Try to build and output a page from outputQueue contents.
  -- We do this after every paragraph.
  -- If page build, returns true and removes boxes used from outputQueue.
  -- Otherwise, returns false.
  pageBuilder = function (self, independent)
    local targetHeight = SILE.length.new({ length = self.frame:height() }) -- XXX Floats

    local pageNodeList
    -- find best place to break, remove these boxes from outputQueue and return them
    pageNodeList, self.state.lastPenalty = SILE.pagebuilder.findBestBreak(self.state.outputQueue, targetHeight)
    if not pageNodeList then -- No break yet
      return false
    end

    local totalHeight = self:totalHeight(pageNodeList)
    local glues, gTotal = self:accumulateGlues(pageNodeList)
    self:adjustGlues(targetHeight, totalHeight, glues, gTotal)

    self:outputLinesToPage(pageNodeList);
    return true
  end,

  -- stretch vertical glues to match targetHeight
  adjustGlues = function(self, targetHeight, totalHeight, glues, gTotal)
    local adjustment = (targetHeight - totalHeight)
    if type(adjustment) == "table" then adjustment = adjustment.length end

    if (adjustment > gTotal.stretch) then adjustment = gTotal.stretch end
    if (adjustment / gTotal.stretch > 0) then 
      for i,g in pairs(glues) do
        g:setGlue(adjustment * g.height.stretch / gTotal.stretch)
      end
    end

    SU.debug("pagebuilder", "Glues for self page adjusted by "..(adjustment/gTotal.stretch) )
  end,

  totalHeight = function(self, pageNodeList)
    local totalHeight
    for i=1,#pageNodeList do
      totalHeight = totalHeight + pageNodeList[i].height + pageNodeList[i].depth
    end
    return totalHeight
  end,

  -- find all glues, return them and their total height
  accumulateGlues = function(self, pageNodeList)
    local glues = {}
    local totalGlueHeight = SILE.length.new()

    for i=1,#pageNodeList do
      if pageNodeList[i]:isVglue() then 
        table.insert(glues,pageNodeList[i]);
        totalGlueHeight = totalGlueHeight + pageNodeList[i].height
      end
    end
    return glues, totalGlueHeight
  end,

  outputLinesToPage = function (self, lines)
    SU.debug("pagebuilder", "OUTPUTTING frame "..self.frame.id);
    local i
    for i = 1,#lines do 
      local l = lines[i]
      if not self.frame.state.totals.pastTop and not (l:isVglue() or l:isPenalty()) then
        self.frame.state.totals.pastTop = true
      end
      if self.frame.state.totals.pastTop then
        l:outputYourself(self, l)
      end
    end
  end,

  initNextFrame = function(self)
    if (self.frame.next and not (self.state.lastPenalty <= supereject_penalty )) then
      self:initFrame(SILE.getFrame(self.frame.next));
    else
      SILE.documentState.documentClass:endPage()
      self:initFrame(SILE.documentState.documentClass:newPage()); -- XXX Hack
    end
    -- Always push back and recalculate. The frame may have a different shape, or
    -- we may be doing clever things like grid typesetting. CPU time is cheap.
    self:pushBack();
  end,

  -- we have nodes on vertical list that did not make it onto previous page.
  -- Move them back to horizontal list since new page might be different
  -- shape than previous page or other trickery may be in progress
  pushBack = function (self)
    SU.debug("typesetter", "Pushing back "..#(self.state.outputQueue).." nodes")
    --self:pushHbox({ width = SILE.length.new({}), value = {glyph = 0} });
    local v
    local function luaSucks (a) v=a return a end

    while luaSucks(table.remove(self.state.outputQueue,1)) do
      if not v:isVglue() and not v:isPenalty() then
        for i=1,#(v.nodes) do
            if v.nodes[i]:isDiscretionary() then
              v.nodes[i].used = 0 -- HACK HACK HACK
            end
            -- HACK HACK HACK HACK HACK
            if not (v.nodes[i]:isGlue() and (v.nodes[i].value == "lskip" or v.nodes[i].value == "rskip")) then
              self.state.nodes[#(self.state.nodes)+1] = v.nodes[i]
            end
        end
      end
    end
    self:leaveHmode();
  end,
  
  leaveHmode = function(self, independent)
    -- create list of lines (vBoxes) from nodes, empty nodes
    local lines = self:boxUpNodes(self.state.nodes)
    self.state.nodes = {};
    self:addLinesToOutputQueue(lines)

    -- after every paragraph we call pageBuilder whcih returns true if
    -- there was enough to build the next page
    if self:pageBuilder() and not independent then
      self:initNextFrame()
    end
  end,

  addLinesToOutputQueue = function(self, lines)
    for index=1, #lines do
      self.state.outputQueue[#(self.state.outputQueue)+1] = lines[index]
    end
  end

  leadingFor = function(self, v, previous)
    -- Insert leading
    SU.debug("typesetter", "   Considering leading between self two lines");
    local prevDepth = 0
    if previous then prevDepth = previous.depth end
    SU.debug("typesetter", "   Depth of previous line was "..tostring(prevDepth));
    local bls = SILE.settings.get("document.baselineskip")
    local d = bls.height - v.height - prevDepth;
    d = d.length
    SU.debug("typesetter", "   Leading height = " .. tostring(bls.height) .. " - " .. tostring(v.height) .. " - " .. tostring(prevDepth) .. " = "..d) ;

    if (d > SILE.settings.get("document.lineskip").height.length) then
      len = SILE.length.new({ length = d, stretch = bls.height.stretch, shrink = bls.height.shrink })
      return SILE.nodefactory.newVglue({height = len});
    else
      return SILE.nodefactory.newVglue(SILE.settings.get("document.lineskip"));
    end
  end,
  
  -- add left and right skips to line based on ocument.lskip, ocument.rskip
  addrlskip = function (self, slice)
    local rskip = SILE.settings.get("document.rskip")
    if rskip and not (rskip.width.length == 0) then
      rskip.value = "rskip"
      table.insert(slice, rskip)
      table.insert(slice, SILE.nodefactory.zeroHbox)
    end
    local lskip = SILE.settings.get("document.lskip")
    if lskip and not (lskip.width.length == 0) then 
      lskip.value = "lskip"
      table.insert(slice, 1, lskip) 
      table.insert(slice, 1, SILE.nodefactory.zeroHbox) 
    end
  end,
  
  -- Rreaks lines at indicated positions
  -- Returns list of {ratio=,nodes=} where each item is line.
  breakpointsToLines = function(self, bp)
    local linestart = 0;
    local lines = {};
    local nodes = self.state.nodes;

    for i,point in pairs(bp) do
      -- point has .position, .width
      if not(point.position == 0) then
        -- not at .position 0

        -- make slice be everything from linestart to point.position
        slice = {}
        local seenHbox = 0
        for j = linestart, point.position do
          slice[#slice+1] = nodes[j]
          if nodes[j] then
            if nodes[j]:isBox() then seenHbox = 1 end
          end
        end

        -- ignore this slice if it does not contain any hbox
        if seenHbox == 0 then break end

        self:addrlskip(slice)   -- add right and left skips to line

        local naturalTotals = self:widthOfSlice(slice)
        self:checkForDescretionaryPunctuationAtEndOfLine(slice, naturalTotals)

        local ratio = self:calculateRatio(point.width, naturalTotals)
        local thisLine = {ratio = ratio , nodes = slice};
        lines[#lines+1] = thisLine
        linestart = point.position+1
      end
    end

    return lines;
  end,

  calculateRatio = function(self, width, naturalTotals)
    local left = (point.width - naturalTotals.length)

    if left < 0 then
      left = left / naturalTotals.shrink
    else
      left = left / naturalTotals.stretch
    end
    
    if left < -1 then left = -1 end
    return left
  end,

  widthOfSlice = function(self, slice)
    local naturalTotals = SILE.length.new({length =0 , stretch =0, shrink = 0})
    for i,node in ipairs(slice) do
      if (node:isBox() or (node:isPenalty() and node.penalty == -inf_bad)) then
        skipping = 0
        if node:isBox() then
          naturalTotals = naturalTotals + node.width
        end
      elseif skipping == 0 then-- and not(node:isGlue() and i == #slice) then
        naturalTotals = naturalTotals + node.width
      end
    end
    return naturalTotals
  end,

  -- If a descretionary hyphen occurs at end of line, mark it as used
  -- and increase the total line lenght by the size of the hyphen
  checkForDescretionaryPunctuationAtEndOfLine = function(self, slice, naturalTotals)
    local i = #slice
    while i > 1 do
      if slice[i]:isGlue() or slice[i] == SILE.nodefactory.zeroHbox then
        -- Do nothing
      elseif (slice[i]:isDiscretionary()) then
        slice[#(slice)].used = 1;
        naturalTotals = naturalTotals + slice[#slice]:prebreakWidth()
      else
        break
      end
      i = i -1
    end
  end,
  
  chuck = function(self) -- emergency shipout everything
    self:leaveHmode(1);
    self:outputLinesToPage(self.state.outputQueue)
    self.state.outputQueue = {}
  end
};

SILE.typesetter = SILE.defaultTypesetter {};

SILE.typesetNaturally = function (frame, f)
  local saveTypesetter = SILE.typesetter
  SILE.typesetter = SILE.defaultTypesetter {};
  SILE.typesetter:init(frame)
  SILE.settings.temporarily(f)
  SILE.typesetter:leaveHmode()
  SILE.typesetter:chuck()
  SILE.typesetter = saveTypesetter
end;

local awful_bad = 1073741823
local inf_bad = 10000
local eject_penalty = -inf_bad
local supereject_penalty = 2 * -inf_bad
local deplorable = 100000

std.string.monkey_patch()
SILE.settings.declare({
  name = "typesetter.widowpenalty", 
  type = "integer",
  default = 150,
  help = "Penalty to be applied to widow lines (at the start of a paragraph)"
})

SILE.settings.declare({
  name = "typesetter.parseppattern", 
  type = "string or integer",
  default = "\n\n+",
  help = "Lua pattern used to separate paragraphs"
})
SILE.settings.declare({
  name = "typesetter.orphanpenalty",
  type = "integer",
  default = 150,
  help = "Penalty to be applied to orphan lines (at the end of a paragraph)"
})

SILE.settings.declare({
  name = "typesetter.parfillskip",
  type = "Glue",
  default = SILE.nodefactory.newGlue("0pt plus 10000pt"),
  help = "Glue added at the end of a paragraph"
})

SILE.settings.declare({
  name = "typesetter.breakwidth",
  type = "Length or nil",
  default = nil,
  help = "Width to break lines at"
})
