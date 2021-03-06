# manage all of the text areas in two-person interview editing

$ = jQuery

DEBUG = false

class ScriptArea
    constructor: (@tam, @name, @speaker, settings) ->
        settings ?= {}
        @locked = if "locked" of settings then settings.locked else false
        
        @el= $("""
        <div>
        <div class="emContainerTAM">
            <div class="emphasisTAM"></div>
        </div>
        <div class="hlContainerTAM">
            <div class="highlightsTAM"></div>
        </div>
        <div class="taContainerTAM">
            <textarea class="txtAreaTAM" name="area#{name}"></textarea>
        </div>
        <div class="overlayContainerTAM">
            <div class="overlaysTAM"></div>
        </div>
        </div>
        """)
        
        @hlContainer = @el.find('.hlContainerTAM')
        @highlights = @el.find('.highlightsTAM')
        @emContainer = @el.find('.emContainerTAM')
        @emphasis = @el.find('.emphasisTAM')
        @overlayContainer = @el.find('.overlayContainerTAM')
        @overlays = @el.find('.overlaysTAM')
        @taContainer = @el.find('.taContainerTAM')
        @area = @el.find(".txtAreaTAM")
        
        containers = [@area, @hlContainer, @highlights,
                      @emContainer, @emphasis, @overlayContainer,
                      @overlays, @taContainer]
        @$containers = $(_.map containers, (c) -> c[0])
        
        @area.bind('copy', (e) => @tam.processCopy(@))
            .bind('cut', (e) => 
                console.log "Cut not supported at this time"
                e.preventDefault()
                return false
                @tam.processCut(@)
            )
            .bind('paste', (e) =>
                if @locked
                    e.preventDefault()
                else
                    @tam.processPaste(@, @area.val())
            )
            .keypress((e) ->
                e.preventDefault if e.which >= 32
                return false
            )
            .keydown((e) =>
                switch e.which
                    when 8
                        # delete
                        e.preventDefault()
                        if not @locked
                            @tam.processDelete(@, "backward")
                        return false
                    when 46
                        # fwd delete
                        e.preventDefault()
                        if not @locked
                            @tam.processDelete(@, "forward")
                        return false
                    when 37, 38, 39, 40
                        # arrow keys
                        if e.shiftKey
                            _.defer @snapSelectionToWord
                    when 13
                        # enter
                        "reauthor"
                        e.preventDefault()
                    when 90
                        # z
                        # prevent undo for now...
                        return false
                    when 190
                        e.preventDefault()
                        if not @locked
                            @addPeriod()
                    when 69
                        e.preventDefault()
                        @insertEmphasisPoint()
                    when 87
                        # w: previous ta
                        tai = @tam.tas.indexOf @
                        if (tai > 0)
                            @tam.tas[tai - 1].area.setSelection(0)
                            @tam.lastFocused = @tam.tas[tai - 1]
                            @tam.container.stop().scrollTo(
                                $(@tam.tas[tai - 1].area), 200, offset: -200)
                        e.preventDefault()
                    when 83 
                        # s: next ta
                        tai = @tam.tas.indexOf @
                        if (tai + 1 < @tam.tas.length)
                            @tam.tas[tai + 1].area.setSelection(0)
                            @tam.lastFocused = @tam.tas[tai + 1]
                            @tam.container.stop().scrollTo(
                                $(@tam.tas[tai + 1].area), 200, offset: -200)
                        e.preventDefault()
                )
            .bind('mousemove', =>
                # TODO: make this more efficient... too slow for every mouse move
                # sel = @area.getSelection()
                # [startInd, endInd] = @rangeIndices(sel.start, sel.end)
                # console.log "highlight in words", startInd, endInd
                # @tam.highlightWordsInWaveform startInd, endInd, @
            )
            .bind('mouseup', @adjustSelection)
        
        @overlays.bind('mouseup', @adjustSelection)
    
    adjustSelection: =>
        @tam.lastFocused = @
        @snapSelectionToWord()
        
        sel = @area.getSelection()
        [startInd, endInd] = @rangeIndices(sel.start, sel.end)
        @tam.highlightWordsInWaveform startInd, endInd, @
       
    _renderWord: (word, isTextArea, wrapLeft, wrapRight) ->
        wrapLeft ?= ""
        wrapRight ?= ""
        
        ending = ['.', '?', '!']
        quoteEnd = '."'
        if word.word[word.word.length - 1] in ending \
        or word.word.slice(-2) is quoteEnd
            if isTextArea
                return "#{wrapLeft}#{word.word}#{wrapRight}\n"
            return "#{wrapLeft}#{word.word}#{wrapRight}<br />"
        
        "#{wrapLeft}#{word.word}#{wrapRight} "

    updateWords: (words) ->
        console.log("UPDATE WORDS") if DEBUG
        if words
            @words = words

        rw = @_renderWord

        badWords = ["UH", "UM", "AH"]

        content = _.reduce @words, ((memo, word) ->
            if word.alignedWord in badWords
                word.emph = true
            return "#{memo}#{rw(word, true)}"), ""
        @val(content)
        
        @tam.dirtyTas.push(@)
        
        @refresh()

        _.defer =>
            if @words.length is 0 and @tam.tas.length isnt 1
                @tam.removeTA @
    
    height: ->
        @area.height()
    
    val: (str) ->
        @area.val(str)
        
    refresh: ->
        console.log("SA REFRESH") if DEBUG
        @updatePos()
        @adjustHeight()
    
    adjustHeight: ->
        console.log("ADJUST HEIGHT OF", @) if DEBUG
        @area.height "20px"
        scrHeight = @area.prop("scrollHeight") + 'px'
        @$containers.height(scrHeight)
        return scrHeight

    snapSelectionToWord: ->
        sel = @area.getSelection()
        console.log sel
        doneEnd = false
        doneStart = false
        return if sel.length is 0

        # all spaces?
        if /^\s+$/.exec sel.text
            @area.collapseSelection()

        text = @area.val()
        
        spaces = [" ", "\n"]

        if sel.length > 0
            # move start right
            while text.charAt(sel.start) in spaces
                doneStart = true
                if sel.start + 1 < sel.end
                    @area.setSelection(sel.start + 1, sel.end)
                    sel = @area.getSelection()
                else
                    break

            # move start left
            while text.charAt(sel.start - 1) not in spaces\
            and text.charAt(sel.start - 1) isnt ""\
            and oldLen isnt sel.length\
            and not doneStart
                oldLen = sel.length
                @area.setSelection sel.start - 1, sel.end
                sel = @area.getSelection()

            # move end left
            while text.charAt(sel.end - 1) in spaces
                doneEnd = true
                if sel.start < sel.end - 1
                    @area.setSelection sel.start, sel.end - 1
                    sel = @area.getSelection()
                else
                    break

            # move end right
            while text.charAt(sel.end) not in spaces\
            and text.charAt(sel.end) isnt ''\
            and oldLen isnt sel.length\
            and not doneEnd
                oldLen = sel.length
                @area.setSelection sel.start, sel.end + 1
                sel = @area.getSelection()
        
        console.log "end of snap", sel
    
    insertEmphasisPoint: ->

        TAAPP.use "addEmphasisPoint"

        @selectWord("backward")
        sel = @area.getSelection()
        @area.setSelection(sel.end)
        word = @range(sel.start, sel.end)[0]
        word.emphasisPoint = true;
        @tam.dirtyTas.push(@)
        @tam.refresh()

    selectWord: (direction) ->
        direction ?= "backward"
        start = @area.getSelection().start
        text = @area.val()
        spaces = [" ", "\n"]
        if direction is "backward"
            other = start - 1
            while text.charAt(other) in spaces\
            and text.charAt(other) isnt ''
                other -= 1
            @area.setSelection other, start

        else if direction is "forward"
            other = start + 2
            while text.charAt(other) in spaces\
            and text.charAt(other) isnt ''
                other += 1
            @area.setSelection start, other
        
        @snapSelectionToWord()
        
    updatePos: ->
        name = @name
        _.each @words, ((elt, i, words) ->
            words[i].taPos = this.total
            words[i].taIdx = name
            this.total += elt.word.length + 1
        ), "total": 0
    
    rangeIndices: (start, end) ->
        for w, i in @words
            if w.taPos >= start
                startInd = i
                break
        for w, i in @words
            if w.taPos < end
                endInd = i
        
        [startInd, endInd] 
    
    range: (start, end) ->
        if not end?
            for word, i in @words
                if word.taPos >= start
                    first = word.taPos
                    break

            return [first, i]
        
        return _.filter @words, (word) ->
            word.taPos >= start and word.taPos < end
    
    addPeriod: ->

        TAAPP.use "addPeriod"

        console.log("Adding a period")
        sel = @area.getSelection()
        range = @range(sel.end)
        if range[1] is 0
            return
        i = range[1] - 1
        
        console.log("adding period to word", @words[i])
        # TODO: check for punctuating period, not any period
        if '.' not in @words[i].word
            @words[i].word += '.'

        # add breath
        breathInds = @tam.breathInds[@speaker]
        topBreaths = _.sortBy breathInds, (bi) => 
            return - @tam.words[bi].likelihood
        
        # limit to best 10 breaths
        # topBreaths = topBreaths[0...10]
        
        breath = topBreaths[Math.floor(Math.random() * topBreaths.length)]
        addInds = [breath]
        
        # let's not do this for now... I don't know

        # if TAAPP?.speech of TAAPP.roomTone
            # create general pause before and after
        if TAAPP.roomTone?
            gp1 = '{gp-0.02}'
            gp2 = '{gp-0.05}'
        
            addInds = [gp1, breath, gp2]
        
        @tam.insertWords addInds, range.end, @
        
    
    highlightWords: (start, end) ->
        rw = @_renderWord
        hlHTML = _.reduce @words, ((memo, word, idx) ->
            wrapLeft = ""
            wrapRight = ""
            if idx is start and (idx is end - 1 or not end?)
                wrapLeft = "<span class='hl'>"
                wrapRight = "</span>"
            else if idx is start
                wrapLeft = "<span class='hl'>"
            else if idx is end - 1
                wrapRight = "</span>"
            return "#{memo}#{rw(word, false, wrapLeft, wrapRight)}"
            ), ""
        
        @highlights.html(hlHTML)
    
    emphasizeWords: ->
        ctx = [-1]
        
        rw = @_renderWord
        
        emphHTML = _.reduce @words, ((memo, word, idx) =>
            wrapLeft = ""
            wrapRight = ""
            if word.origPos? and word.origPos - 1 isnt this[0]
                wrapLeft += "<span class='editLocation'>"
                wrapRight += "</span>"
                # out = "<span class='editLocation'>#{out}</span>"
            if word.emph? and word.emph
                wrapLeft += "<span class='emph'>"
                wrapRight += "</span>"
                # out = "<span class='emph'>#{out}</span>"
            if word.emphasisPoint? and word.emphasisPoint
                wrapLeft += "<span class='ePt'>"
                wrapRight += "</span>"
            if word.alignedWord is "sp" or word.alignedWord is "gp"
                wrapLeft += "<span class='pause'>"
                wrapRight += "</span>"
                # out = "<span class='pause'>#{out}</span>"
            else if word.alignedWord is "{BR}"
                wrapLeft += "<span class='breath'>"
                wrapRight += "</span>"
            else if word.alignedWord is @words[idx - 1]?.alignedWord\
            or @words[idx + 1]?.alignedWord is word.alignedWord
                wrapLeft += "<span class='repeatedWord'>"
                wrapRight += "</span>"
            this[0] = word.origPos
            return "#{memo}#{rw(word, false, wrapLeft, wrapRight)}"
            ), "", ctx
        @emphasis.html(emphHTML)
    
    insertDupeOverlays: (dupes, dupeInfo) ->
        console.log("SA INSERT DUPE OVERLAYS", @) if DEBUG
        box = @overlays
        context =
            dupeOrder: []
            bounds: []
        
        dupeOrder = []
        dupeStartsFirsts = dupeInfo.firsts
        dupeStarts = dupeInfo.starts
        
        offset = @tam.taIndexSpan[@tam.tas.indexOf @]
        
        dupeDropdownWrapLeft = """
            <span class="dropdown overlay">
                <span class="dropdown-toggle">
        """
        
        dupeDropdownWrapRight = """
                </span>
                <ul class="dropdown-menu" role="menu" aria-labelledby="dLabel">
                    <li class="disabled"><a><%= header %></a></li>
                    <% _.each(dupes[dupeIdx], function (elt) { %>
                        <li><span 
                               class="dupeOpt"
                               tabindex="-1">
                               <i class="icon-play dupePlayButton"></i>
                               <div style="position:relative; display:inline-block">
                               <span class="copyButton"><%= elt[1] %></span>
                               </div>
                            </span>
                        </li>
                    <% }) %>
                </ul>
            </span>
        """
        rw = @_renderWord
        locked = @locked
        boxHTML = _.reduce @words, ((memo, word, idx, words) ->
            dupeIdx = dupeStartsFirsts.indexOf word.origPos
            wrapLeft = ""
            wrapRight = ""
            if dupeIdx isnt -1
                sentenceEnd = idx
                d = dupeStarts[dupeIdx]
                allIdx = d.idxInDupes
                while sentenceEnd < words.length\
                and words[sentenceEnd].origPos >= d.dElt[0][0]\
                and words[sentenceEnd].origPos <= d.dElt[0][1]
                    sentenceEnd += 1
                
                this.dupeOrder.push allIdx
                this.bounds.push [idx, sentenceEnd - 1]
                
                wrapLeft = dupeDropdownWrapLeft
                header = if locked then\
                    "Similar sentences (click to copy)" else\
                    "Similar sentences"
                wrapRight = _.template(dupeDropdownWrapRight,
                    header: header,
                    dupeIdx: allIdx,
                    dupes: dupes)

            if word.alignedWord is "sp" or word.alignedWord is "gp"
                wrapLeft += "<span class='pauseOverlay'>"
                wrapRight += "</span>"
            if word.alignedWord is "{BR}"
                wrapLeft += "<span class='breathOverlay'>"
                wrapRight += "</span>"
            return "#{memo}#{rw(word, false, wrapLeft, wrapRight)}"
            ), "", context
        
        box.html(boxHTML)
        
        # add bootstrap dropdown hook
        # and add event handlers because we were copying the raw html above
        self = @
        taWidth = @area.width()
        
        @area.unbind('.tam')
        .bind('click.tam', -> 
            console.log "clicked on the box"
            $('.dropdown.open').removeClass('open')
        )
        
        box.find('.dropdown-toggle')
        .dropdown()
        .each((i) ->
            pos = $(this).offset()
            eltPos = self.area.offset()
            dupe = dupes[context.dupeOrder[i]]
            start = context.bounds[i][0]
            end = context.bounds[i][1]
            
            
            
            $(this).click( ->

                TAAPP.use "viewSimilarSentences"

                console.log "start", start, "end", end
                self.area.setSelection self.words[start].taPos,
                    self.words[end].taPos + self.words[end].word.length
            )
            .next('.dropdown-menu').css(
                left: "#{-pos.left + eltPos.left + 10}px"
                width: "#{taWidth - 20}px"
            )
            .find('span.dupeOpt')
            .each((j) ->
                if locked
                    $(this).closest('.dropdown').addClass('open');
                    "zero clipboard is obnoxious for now"
                    indices = [dupe[j][0][0]..dupe[j][0][1]]
                    $(@).find('.copyButton')
                        .attr("data-clipboard-text", 
                            self.tam.generateCopyTextFromIndices indices)
                        .zclip(
                            path: "static/swf/ZeroClipboard.swf",
                            copy: self.tam.generateCopyTextFromIndices(indices),
                            afterCopy: (->
                                self.area.focus()
                                console.log "COPPY", $(this).closest('.dropdown')
                                $(this).closest('.dropdown').removeClass('open')
                            )
                        )
                    # this is a hack but I don't know why the offset is wrong
                    # with zclip/ZeroClipboard
                    $(this).find('.zclip').css(
                        top: "-4px"
                    )
                    $(this).closest('.dropdown').removeClass('open');
                else
                    # set up text replacement in editing area
                    $(@).click((event) ->

                        TAAPP.use "replaceSentence"

                        newPos = self.replaceWords start, end,
                            dupe[j][0][0], dupe[j][0][1]
                        self.area.setSelection newPos[0], newPos[1]
                        return false
                    )
                
                $(@).find('.dupePlayButton')
                .click((event) ->

                    TAAPP.use "playSimilarSentence"

                    audiostart = self.tam.words[dupe[j][0][0]].start
                    audioend = self.tam.words[dupe[j][0][1]].end
                    TAAPP.origSound.play
                        from: audiostart * 1000.0
                        to: audioend * 1000.0
                        onstop: ->
                            if $(this).closest('.dropdown').hasClass('open')
                                self.area.focus()
                    event.stopPropagation()
                )
            )
        )
        
    replaceWords: (c1, c2, w1, w2) ->
        # replace words from c1 to c2 in @words
        # with words w1 through w2 in the original words
        @tam.replaceWords c1, c2, w1, w2, @, @words[c1].taPos

class TextAreaManager
    constructor: (@el, @speakers, @words, @current, settings) ->
        settings ?= {}
        @locked = if "locked" of settings then settings.locked else false
        @textAlignedWfs = if "wfs" of settings then settings.wfs else null

        @headerTable = $(document.createElement 'table')
            .attr("width", "100%")
            .appendTo(@el)
        @container = $(document.createElement 'div')
            .css(
                "overflow-x": "hidden"
                "overflow-y": "auto"
            )
            .appendTo(@el)

        @table = $(document.createElement 'table')
            .attr("width", "100%")
            .appendTo(@container)
        
        # create a column for each speaker
        tr = $(document.createElement 'tr')
            .appendTo(@headerTable)
        _.each @speakers, (speaker) =>
            th = document.createElement 'th'
            $(th).html(speaker)
                .width("#{100/@speakers.length}%")
                .appendTo(tr)

        @tas = []
        @taIndexSpan = []
        @areas = []
        @dirtyTas = []
        @draw()
        
        # create breaths listing
        @breathInds = {}
        for speaker in @speakers
            @breathInds[speaker] = []
        _.each @words, (word, i, cur) =>
            if word.alignedWord is "{BR}"
                j = i
                while j < @words.length
                    if "speaker" not of @words[j]
                        j++
                    else
                        break
                return if j is @words.length
                if "speaker" of @words[j]
                    @breathInds[@words[j].speaker].push i

        # init scrollTo
        @el.scrollTo 0
        
    
    _tr: (index) ->
        tr = $(document.createElement 'tr')
        _.each @speakers, (speaker) ->
            td = $(document.createElement('td'))
            tr.append(td)
        
        tr.find("td")
            .width("#{100/@speakers.length}%")
        
        if index?
            if index is 0
                tr.prependTo(@table)
            else
                tr.insertAfter(@table.find('tr').eq(index - 1))
        else
            tr.appendTo(@table)
            
        tr
    
    _newScriptArea: (name, speaker, index) ->
        ta = new ScriptArea this, name, speaker, locked: @locked
        if index?
            @tas.splice(index, 0, ta)
            @areas.splice(index, 0, ta.area)
        else
            @tas.push ta
            @areas.push ta.area
        ta.el
    
    refresh: ->
        console.log("TAM REFRESH") if DEBUG
        @dirtyTas = _.uniq(@dirtyTas)

        # console.log("Dirty TAs", @dirtyTas)
        
        ta.name = i for ta, i in @tas

        @updatePos()
        @adjustHeight()
        @emphasizeWords()
        @insertDupeOverlays @dupes, @dupeInfo
        
        if @textAlignedWfs?
            $(_.values(@textAlignedWfs)).textAlignedWaveform
                currentWords: @current
        
        @dirtyTas = []
    
    adjustHeight: (forceAll) ->
        console.log("ADJUST HEIGHT OF TAM") if DEBUG
        # height of scriptareas
        # ta.adjustHeight() for ta in @tas

        forceAll ?= false

        taSet = if forceAll then @tas else @dirtyTas

        for ta in taSet
            height = ta.adjustHeight()
            ta.el.closest('tr').height(height)

        # update height of row
        # for i in [0...@tas.length]
        #     @table.find('tr').eq(i)
        #         .height(@tas[i].height())

        # update height of outer element
        console.log("container height", window.innerHeight - @el.offset().top - 50)
        @container.height(window.innerHeight - @el.offset().top - 50)
        console.log("el height", window.innerHeight - @el.offset().top - 50)
        @el.height(window.innerHeight - @el.offset().top - 50)
    
    draw: ->
        @table.find("tr").remove()
        lastSpeaker = @speakers[0]
        count = 0
        @taIndexSpan = [0]
        _.each @current, (word, i) =>
            if i is 0 
                col = 0
                tr = @_tr()
                tr.find("td").eq(col)
                    .append(@_newScriptArea(count++, lastSpeaker))
            else if word.speaker? and word.speaker isnt lastSpeaker
                @taIndexSpan.push i
                col = @speakers.indexOf(word.speaker)
                tr = @_tr()
                tr.find("td").eq(col)
                    .append(@_newScriptArea(count++, word.speaker))
                lastSpeaker = word.speaker

        _.each @taIndexSpan, (start, i) =>
            # update previous text area

            if i is @taIndexSpan.length - 1
                words = @current[start..]
            else
                words = @current[start...@taIndexSpan[i + 1]]

            @tas[i].updateWords words

        @dirtyTas = @tas[..]
        @refresh()
        
        @lastFocused = @tas[0]

    pruneByTAPos: (start, end, ta) ->
        console.log("PRUNE BY TA POS") if DEBUG
        match = []
        _.each(ta.words, (word, idx) ->
            if word.taPos >= start and word.taPos < end
                match.push idx
            )
        console.log "prune by TA", match[0], _.last(match)
        @pruneByTAIndex(match[0], _.last(match) + 1, ta)
    
    pruneByTAIndex: (start, end, ta, refresh) ->
        console.log("PRUNE BY TA INDEX") if DEBUG
        refresh ?= true
        taIndex = @tas.indexOf ta
        offset = @taIndexSpan[taIndex]
        @pruneCurrent(start + offset, end + offset, refresh)

    pruneCurrent: (start, end, refresh) ->
        console.log("PRUNE CURRENT") if DEBUG
        refresh ?= true



        cutWords = @current.splice start, end - start
        console.log("start", start, "end", end, "cutwords", cutWords)
        # TODO: BUG: will a problem if we have words from more than one TA

        taIndex = cutWords[0].taIdx
        ta = @tas[taIndex]

        console.log "taIndex", taIndex, "ta", ta

        # update the script area trackers
        for txtarea, i in @tas
            if i > taIndex
                @taIndexSpan[i] -= end - start

        if taIndex is @tas.length - 1
            ta.updateWords @current[@taIndexSpan[taIndex]..]
        else
            console.log "Prune current, updating ta with words",
                 @taIndexSpan[taIndex],
                 @taIndexSpan[taIndex + 1] - 1
            ta.updateWords @current\
                [@taIndexSpan[taIndex]...@taIndexSpan[taIndex + 1]]
        
        @refresh() if refresh

    pruneAll: ->
        for ta in @tas
            ta.updateWords([])
        @current.splice(0, @current.length)
        # for ta in @tas
            # @pruneByTAIndex 0, ta.words.length, ta, false
        @refresh()

    highlightWordsInWaveform: (start, end, ta) ->
        if @textAlignedWfs?
            offset = @taIndexSpan[@tas.indexOf ta]
            if @highlightedWordsRange?[0] isnt offset + start or
            @highlightedWordsRange?[1] isnt offset + end
                @highlightedWordsRange = [offset + start, offset + end]

                # highlight speaker's waveform
                $(@textAlignedWfs[ta.speaker]).textAlignedWaveform
                    highlightedWordsRange: @highlightedWordsRange
                
                # unhighlight others
                for speaker in @speakers
                    if speaker isnt ta.speaker
                        $(@textAlignedWfs[speaker]).textAlignedWaveform
                            highlightedWordsRange: undefined



    highlightWords: (start, end) ->
        if start is -1
            @currentHighlight = undefined
            ta.highlights.html("") for ta in @tas
            return
        
        if @currentHighlight?[0] > start and @currentHighlight?[0] < start + 3
            return
        
        @currentHighlight = [start, end]
        
        # find the ta that contains the highlight
        for ta, i in @tas
            if @taIndexSpan[i] > start
                break
        if i isnt 0
            ta = @tas[i - 1]
            offset = @taIndexSpan[i - 1]
        else
            ta = @tas[0]
            offset = @taIndexSpan[0]
            
        t.highlights.html("") for t in @tas

        if end?
            newEnd = end - offset
        
        ta.highlightWords start - offset, newEnd
    
    emphasizeWords: ->
        ta.emphasizeWords() for ta in @dirtyTas
        
    updatePos: ->
        @highlightWords -1
        count = 0
        @taIndexSpan = []
        for ta, i in @tas
            ta.name = i
            @taIndexSpan.push count
            count += ta.words.length
        ta.updatePos() for ta in @dirtyTas

    
    clean: (ta) ->
        # assume we'll either have
        # RIGHT WRONG RIGHT
        # or RIGHT WRONG
        # or WRONG RIGHT
        # or RIGHT
        # or WRONG
        
        tai = @tas.indexOf ta
        offset = @taIndexSpan[tai]
        
        segments = []
        pattern = []
        speakers = []
                
        for word, i in ta.words
            if word.speaker? and word.speaker isnt lastSpeaker
                segments.push i
                speakers.push word.speaker
                pattern.push(word.speaker is ta.speaker)
                lastSpeaker = word.speaker
        
        if pattern.length is 1 and pattern[0]
            @refresh()
            return

        if pattern.length is 1 and not pattern[0]
            # right wrong right
            words = ta.words[..]
            
            col = @speakers.indexOf lastSpeaker
            ta.speaker = lastSpeaker

            # move the content to a different column
            ta.el.closest('tr')
                .find('td')
                .eq(col)
                .append(ta.el)

            @refresh()
            return
        
        if pattern.length is 2 and pattern[0]
            # right wrong
            words = ta.words[segments[1]..]
            if tai is @tas.length - 1
                console.log "New row"
                # new row
                col = @speakers.indexOf(speakers[1])

                tr = @_tr(tai + 1)

                # tr = @_tr(@table.find('tr').eq(tai))

                tr.find("td").eq(col)
                    .append(@_newScriptArea(@tas.length, speakers[1], tai + 1))

                # update words
                ta.updateWords ta.words[0...segments[1]]
                @tas[@tas.length - 1].updateWords words
                # @taIndexSpan.push offset + ta.words.length
                
                @tas[@tas.length - 1].area.setSelection 0, 0
                @refresh()
                
            else if @tas[tai + 1].speaker is speakers[1]
                console.log "Inserting in next row"
                console.log(@tas, tai)
                nextTa = @tas[tai + 1]
                ta.updateWords ta.words[0...segments[1]]
                nextTa.updateWords words.concat(nextTa.words)
                # @taIndexSpan[tai + 1] -= words.length
                
                nextTa.area.setSelection 0, 0
                @refresh()
            else
                window.alert "should not get here (right wrong pattern)"
                
            console.log "CLEAN: @tas", @tas, "taIndexSpan", @taIndexSpan
            return
            
        if pattern.length is 2 and pattern[1]
            # wrong right
            words = ta.words[0...segments[1]]
            if tai is 0
                console.log "New row (wrong right)"
                col = @speakers.indexOf speakers[0]

                tr = @_tr(0)

                # if tai is 0
                #     tr = @_tr()
                # else
                #     tr = @_tr(@table.find('tr').eq(tai))
                tr.find("td").eq(col)
                    .append(@_newScriptArea(@tas.length, speakers[0], 0))
                
                # update words
                ta.updateWords ta.words[segments[1]..]
                @tas[0].updateWords words
                # @taIndexSpan.splice(1, 0, words.length)
                            
            else if @tas[tai - 1].speaker is speakers[0]
                prevTa = @tas[tai - 1]
                ta.updateWords ta.words[segments[1]..]
                prevTa.updateWords prevTa.words.concat(words)
                # @taIndexSpan[tai] += words.length
            else
                window.alert "should not get here (wrong right pattern)"
            ta.area.setSelection(0, 0)
            @refresh()
            return
        
        if pattern.length is 3
            # right wrong right
            words = ta.words[..]
            
            col = @speakers.indexOf speakers[1]

            tr = @_tr(tai + 1)

            # if tai is 0
            #     tr = @_tr()
            # else
            #     tr = @_tr(@table.find('tr').eq(tai))
            tr.find("td").eq(col)
                .append(@_newScriptArea(@tas.length, speakers[1], tai + 1))
            
            col = @speakers.indexOf speakers[2]

            tr = @_tr(tai + 2)

            # tr = @_tr(@table.find('tr').eq(tai + 1))
            tr.find("td").eq(col)
                .append(@_newScriptArea(@tas.length, speakers[2], tai + 2))
            
            # update words
            ta.updateWords words[0...segments[1]]
            @tas[tai + 1].updateWords words[segments[1]...segments[2]]
            @tas[tai + 2].updateWords words[segments[2]..]
            
            # @taIndexSpan.splice tai + 1, 0,
                # @taIndexSpan[tai] + ta.words.length,
                # @taIndexSpan[tai] + ta.words.length + @tas[tai + 1].words.length
            
            @refresh()
            
            @tas[tai + 1].area.setSelection(0, 0)
            return

    processDelete: (ta, direction) ->

        TAAPP.use "delete"

        console.log("PROCESSDELETE") if DEBUG
        if window.TAAPP.sound
            window.TAAPP.sound.stop()

        ta.snapSelectionToWord()
        sel = ta.area.getSelection()
        
        # if nothing is selected, select a word
        if sel.length is 0
            ta.selectWord(direction, true)
        
        sel = ta.area.getSelection()
        end = sel.end
        
        text = ta.area.val()
        spaces = [" ", "\n"]
        while text.charAt(end) in spaces
            end += 1
        
        console.log "calling prune by ta pos with start", sel.start, "end", end
        @pruneByTAPos(sel.start, end, ta)
        
        ta.area.setSelection(sel.start, sel.start)
        # @refresh()
    
    insertEmphasisPoint: (ta) ->

        ta ?= @lastFocused
        ta.insertEmphasisPoint()

    insertWords: (indices, pos, ta) ->
        # pos and ta are optional
        console.log("INSERT WORDS", indices, "POS", pos, "TA", ta)

        ta ?= @lastFocused
        pos ?= ta.area.getSelection().start
        
        # find location
        taIndex = @tas.indexOf ta
        offset = @taIndexSpan[taIndex]

        for word, loc in ta.words
            if word.taPos >= pos
                break
            else if loc is ta.words.length - 1
                loc = ta.words.length
        
        ctx = 
            first: undefined
            last: undefined
            words: @words
            
        if not _.isArray indices
            indices = [indices]
        
        words = _.map indices, ((idx) ->
            if idx.toString().split('-')[0] is '{gp'
                tmp = clone(TAAPP.roomTone);
                tmp.word = idx
                tmp.pauseLength = parseFloat idx.split('-')[1]
                this.first ?= tmp
                this.last = tmp
                return tmp
                
            tmp = clone(this.words[idx])
            this.first ?= tmp
            this.last = tmp
            return tmp
            ), ctx
        
        # insert them
        args = [loc + offset, 0].concat words
        Array::splice.apply @current, args

        # bookkeeping
        for i in [0...@tas.length]
            if i > taIndex
                @taIndexSpan[i] += words.length
        
        
        # now we have to check everything to make
        # sure we create the right boxes for the
        # right speakers
        
        # well, in a second...
        
        @dirtyTas.push(ta)

        if taIndex is @tas.length - 1
            ta.updateWords @current[@taIndexSpan[taIndex]..]
        else
            ta.updateWords @current[@taIndexSpan[taIndex]...@taIndexSpan[taIndex + 1]]
        
        @clean ta
        @refresh()
        
        # set the selection position after the inserted words
        newEnd = ctx.last.taPos + ctx.last.word.length
        ta.area.setSelection newEnd, newEnd
        
        return @current.indexOf(ctx.first)

        # newStart = ctx.first.taPos
        # newEnd = ctx.last.taPos + ctx.last.word.length
        # 
        # [newStart, newEnd]
    
    processPaste: (ta, a) ->

        TAAPP.use "paste"

        _.defer =>
            parse_paste = /(?:\[(\d+|gp),(e?)\]([^|]+)\|)/g
            bRes = false
            pastedWords = []
            b = ta.area.val()
            sel = ta.area.getSelection()
            spaces = [" ", "\n"]
            if a.length - b.length + sel.start isnt 0\
            and a.charAt(a.length - b.length + sel.start) not in spaces\
            and a.charAt(a.length - b.length + sel.start - 1) not in spaces
                console.log "couldn't paste", a.length, b.length, sel.start
                # can't insert here: middle of a word
                ta.area.val(a)
                @refresh()
                return
            
            count = 0
            epts = []
            while result = parse_paste.exec b
                bRes = true
                if result[1] is 'gp'
                    pastedWords.push result[3]
                else
                    pastedWords.push parseInt(result[1], 10)
                if result[2] is 'e'
                    epts.push(count)
                count += 1
            
            if bRes
                firstIdx = @insertWords pastedWords, a.length - b.length + sel.start, ta

                @current[firstIdx + ept].emphasisPoint = true for ept in epts
                for ept in epts
                    for ta, tai in @tas
                        if @taIndexSpan[tai] <= ept \
                        and @taIndexSpan[tai] + ta.words.length > ept
                            @dirtyTas.push(ta)
                @refresh() if epts.length isnt 0

                console.log "taindexspan after clean", @taIndexSpan
                return
            
            ta.area.val(a)
            @refresh()

    generateCopyTextFromIndices: (indices) ->
        wrds= (@current[i] for i in indices)
        mod = _.reduce wrds, ((memo, wrd) =>
            if wrd.alignedWord is "gp"
                return memo + '[gp]' + wrd.word + '|'
            for w, j in @words
                if w.start is wrd.start and w.end is wrd.end
                    break
            return "#{memo}[#{j}]#{wrd.word}|"
            ), ""
        return mod

    processCopy: (ta) ->

        TAAPP.use "copy"

        selection = window.getSelection()
        newdiv = document.createElement 'div'
        sel = ta.area.getSelection()
        wrds = ta.range sel.start, sel.end
        
        mod = _.reduce wrds, ((memo, wrd) =>
            ept = ''
            if "emphasisPoint" of wrd and wrd.emphasisPoint
                ept = 'e'
            if wrd.alignedWord is "gp"
                return "#{memo}[gp,#{ept}]#{wrd.word}|"
            for w, j in @words
                if w.start is wrd.start and w.end is wrd.end
                    break
            return "#{memo}[#{j},#{ept}]#{wrd.word}|"
            ), ""
        
        $(newdiv).css(position: "absolute", left: "-99999px")
            .html(mod)
            .appendTo("body")
        selection.selectAllChildren(newdiv)
        _.defer ->
            $(newdiv).remove()

    processCut: (ta) ->
        sel = ta.area.getSelection()
        wrds = ta.range(sel.start, sel.end)
        newOut = ta.area.val()
        
        mod = _.reduce wrds, ((memo, wrd) =>
            if wrd.alignedWord is "gp"
                return memo + '[gp]' + wrd.word + '|'
            for w, j in @words
                if w.start is wrd.start and w.end is wrd.end
                    break
            return "#{memo}[#{j}]#{wrd.word}|"
            ), ""
        
        newOut = newOut[0...sel.start] + mod + newOut[sel.end + 1..]
        ta.area.val(newOut)
            .setSelection(sel.start, sel.start + mod.length)
    
    insertDupeOverlays: (@dupes, @dupeInfo, forceAll) ->
        console.log("INSERT DUPE OVERLAYS") if DEBUG
        forceAll ?= false
        console.log("DIRTY:", @dirtyTas) if DEBUG
        return if not @dupes?
        
        if forceAll
            ta.insertDupeOverlays @dupes, @dupeInfo for ta in @tas
            ta.adjustHeight() for ta in @tas
        else
            ta.insertDupeOverlays @dupes, @dupeInfo for ta in @dirtyTas
    
    replaceWords: (c1, c2, w1, w2, ta, pos) ->
        # replace words from c1 to c2 in @current
        # with words w1 through w2 in the original words
        @pruneByTAIndex c1, c2 + 1, ta
        return @insertWords _.range(w1, w2 + 1), pos, ta
    
    removeTA: (ta) ->
        console.log("INDEX", @tas.indexOf ta, "REMOVING TA", ta)

        taIndex = @tas.indexOf ta
        @tas.splice taIndex, 1
        @taIndexSpan.splice taIndex, 1
        @table.find("tr").eq(taIndex).remove()
        
        console.log("TA", ta, "taIndex", taIndex, "@TAS", @tas)

        if taIndex isnt 0 and taIndex < @tas.length\
        and @tas[taIndex - 1].speaker is @tas[taIndex].speaker
            # combine the two
            console.log("### combining 2 text areas")
            @tas[taIndex - 1].updateWords(
                @tas[taIndex - 1].words.concat @tas[taIndex].words
            )
            @removeTA @tas[taIndex]

        # mark tas after this one as dirty (they need to run updatePos)
        Array::push.apply @dirtyTas, @tas.slice(taIndex)

        @refresh()
    
    log: (statements...) ->
        args = ["[TAM]"].concat statements
        console.log args...

window.TextAreaManager = TextAreaManager