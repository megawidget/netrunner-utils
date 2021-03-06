@decks =
    Corp: undefined
    Runner: undefined

@makeDeck = (side) ->
    result = switch side
        when 'Corp' then new CorpDeck(@cards)
        when 'Runner' then new RunnerDeck(@cards)

sort_cards_tsv_f = (a, b) ->
    a_rank = $.indexOf(window.card_types_order[a[1].side], a[1].type)
    b_rank = $.indexOf(window.card_types_order[b[1].side], b[1].type)
    if a_rank > b_rank
        return 1
    if a_rank < b_rank
        return -1
    if a[1].name.toLowerCase() > b[1].name.toLowerCase()
        return 1
    return -1

limit_one_cards = ['03004'] #Director Haas' Pet Project

class BaseDeck
    constructor: (cards) ->
        @all_cards = cards
        @cards = {}
        @current_influence = 0
        @identity = undefined
        @faction = undefined
        @size = 0
        @modified = false
        $(document).on('add_to_deck', (card) => @addCard(card))
        $(document).on('remove_from_deck', (card) => @removeCard(card))
        $(document).on('clear_deck', (side) => if side is @side then @clear())
        $(document).on('export_to_o8d', (side, name) => if side is @side then @exportToO8D(name))
        $(document).on('export_to_tsv', (side, name) => if side is @side then @exportToTSV(name))
        $(document).on('save_deck', (side, name) => if side is @side then @save(name))
        $(document).on('load_deck', (side, name) => if side is @side then @load(name))
        $(document).on('delete_deck', (side, name) => if side is @side then @delete(name))
    
    getIdentity: -> return if @identity? then '<strong>' + @identity.name + '</strong> (' + @faction + ')' else '??'
    getSize: -> return @size
    getInfluence: -> return @current_influence
    isModified: -> return if @modified then '*' else ''

    #TODO: this is likely inefficient, but let's not suffer from premature
    #optimization, esp. for ~49 card decks
    fillOrderedDivsByType: (type, parent) ->
        parent.empty()
        result = []
        total_count = 0
        for card_id, count of @cards
            card = @all_cards[card_id]
            if card.type is type
                total_count += count
                elem = $.create('<div>')
                elem[0].style.width = '100%'
                elem[0].style.position = 'relative'
                elem[0].style.zIndex = 0
                elem.name = card.name
                elem.subtype = card.subtype
                name = $.create('<div>').addClass('card_header').addClass('clickable')
                name[0].style.zIndex = 10
                name[0].style.width = '100%'
                name[0].style.position = 'relative'
                name[0].style.float = 'left'
                name[0].innerHTML = card.name
                name[0].onclick = do (card) ->
                    () => $(document).trigger('add_to_deck', card)
                name[0].oncontextmenu = do (card) ->
                    () => $(document).trigger('remove_from_deck', card); return false
                elem.append(name)
                bar = $.create('<div>').addClass('progress_bar')
                bar.addClass(card.faction.toLowerCase().replace(' ', '_'))
                bar[0].style.width = (100 / 3 * count) + '%'
                bar[0].style.left = 0
                bar[0].style.zIndex = 5
                bar[0].style.display = "inline"
                elem.append(bar)
                clear = $.create('<div>')
                clear[0].style.clear = 'both'
                elem.append(clear)
                result.push(elem)
        result.sort( window.card_sort_f )
        for div in result
            parent.append(div[0])
        return total_count

    addCard: (card) ->
        if card.side isnt @side
            return
        if card.type is 'Identity'
            if @identity?
                @modified = true
                $(document).trigger('on_card_removed', @identity)
            @identity = card
            @faction = card.faction
            @removeInvalidAgendas()
            @removeInvalidCards()
            @recalculateInfluence()
            @modified = true
            $(document).trigger('on_card_added', card)
            return
        if not card.influence? and @identity? and (card.faction isnt @faction and card.faction isnt 'Neutral')
            return
        if @identity? and @identity.card_id is '03002' and card.faction is 'Jinteki' #engineered for success
            return
        if @cards[card.card_id]?
            if @cards[card.card_id] == 3
                return
            if card.card_id in limit_one_cards
                return
            @cards[card.card_id] += 1
        else
            @cards[card.card_id] = 1
        @size += 1
        if card.type is 'Agenda'
            if not @identity? and card.faction isnt 'Neutral'
                @faction = card.faction
                @removeInvalidAgendas()
            @agenda_points += card.agenda_points
        if card.faction isnt @faction and card.influence?
            if not (@identity? and @identity.card_id is '03029' and card.type is 'Program' and @cards[card.card_id] == 1) #the professor
                @current_influence += card.influence
        @modified = true
        $(document).trigger('on_card_added', card)
        return
    
    removeCard: (card) ->
        if card.side isnt @side
            return
        if card.type is 'Identity'
            if @identity? and card.card_id is @identity.card_id
                @modified = true
                @identity = undefined
                @removeInvalidAgendas()
                $(document).trigger('on_card_removed', card)
            return
        if not @cards[card.card_id]?
            return
        @cards[card.card_id] -= 1
        if card.type is 'Agenda'
            @agenda_points -= card.agenda_points
        if card.faction isnt @faction and card.influence?
            if not (@identity? and @identity.card_id is '03029' and card.type is 'Program' and @cards[card.card_id] == 0) #the professor
                @current_influence -= card.influence
        if @cards[card.card_id] == 0
            delete @cards[card.card_id]
        @size -= 1
        @modified = true
        $(document).trigger('on_card_removed', card)
        return

    clear: () ->
        @cards = {}
        @current_influence = 0
        @identity = undefined
        @faction = undefined
        @size = 0
        @modified = true
        $(document).trigger('on_deck_cleared', @side)

    getInfluenceLimit: ->
        return if @identity? then @identity.influence_limit else 15

    getDeckSizeLimit: ->
        return if @identity? then @identity.min_deck_size else 45
    
    recalculateInfluence: ->
        @current_influence = 0
        for card_id, card_count of @cards
            card = @all_cards[card_id]
            if card.faction isnt @faction and card.influence?
                if @identity? and @identity.card_id is '03029' and card.type is 'Program' #the professor
                    @current_influence += card.influence * (card_count - 1)
                else
                    @current_influence += card.influence * card_count
    
    validateDeck: ->
        invalid_properties = []
        if not @identity?
            invalid_properties.push('getIdentity')
        if @current_influence > @getInfluenceLimit()
            invalid_properties.push('getInfluence')
        if @size < @getDeckSizeLimit()
            invalid_properties.push('getSize')
        return invalid_properties

    makeOctgnCard: (card_id) ->
        card = @all_cards[card_id]
        return "<card qty=\"#{@cards[card_id]}\" id=\"#{card.id}\">#{$.escape(card.name)}</card>\n"

    exportToTSV: (name) ->
        result = '#\tcard_id\tname\n'
        if @identity?
            result += "#\t\t#{@identity.type}\n"
            result += "1\t#{@identity.card_id}\t#{$.escape(@identity.name)}\n"
        sorted_cards = ([count, @all_cards[card_id]] for card_id, count of @cards)
        sorted_cards.sort(sort_cards_tsv_f)
        last_type = ''
        for i in sorted_cards
            if i[1].type isnt last_type
                last_type = i[1].type
                result += "#\n"
                result += "#\t\t#{last_type}\n"
            result += "#{i[0]}\t#{i[1].card_id}\t#{$.escape(i[1].name)}\n"
        b = new Blob([result], {"data:text/plain;charset=utf-8"})
        faction = if @faction? then @faction else '???'
        identity = if @identity? then @identity.short_name else '???'
        full_name = [faction, identity, name]
        full_name = full_name.join(' - ') + '.tsv'
        saveAs(b, full_name)

    exportToO8D: (name) ->
        for card_id, count of @cards
            game_id = @all_cards[card_id].game_id
            break
        result = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
        result += "<deck game=\"#{game_id}\">"
        result += "<section name=\"Identity\">"
        if @identity?
            result += "<card qty=\"1\" id=\"#{@identity.id}\">#{$.escape(@identity.name)}</card>\n"
        result += "</section>\n"
        result += "<section name=\"R&amp;D / Stack\">\n"
        result += (@makeOctgnCard(card_id) for card_id, count of @cards).join('')
        result += "</section>\n"
        result += "</deck>\n"
        b = new Blob([result], {"data:application/xml;charset=utf-8"})
        faction = if @faction? then @faction else '???'
        identity = if @identity? then @identity.short_name else '???'
        full_name = [faction, identity, name]
        full_name = full_name.join(' - ') + '.o8d'
        saveAs(b, full_name)
    
    loadLastDeck: ->
        name = localStorage["#{@side}:last_deck"]
        if name?
            @load(name)

    save: (name) ->
        key = "deck:#{name}"
        card_id = if @identity? then @identity.card_id else undefined
        localStorage[key] = JSON.stringify({cards: @cards, current_influence: @current_influence, identity: card_id, faction: @faction, size: @size, agenda_points: @agenda_points})
        localStorage["#{@side}:last_deck"] = name
        decks_key = "#{@side}:decks"
        decks = localStorage[decks_key]
        if decks?
            decks = JSON.parse(decks)
        else
            decks = {}
        decks[name] = true
        localStorage[decks_key] = JSON.stringify(decks)
        @modified = false
        $(document).trigger('on_deck_saved', [@side, @faction, card_id, name])

    load: (name) ->
        key = "deck:#{name}"
        data = localStorage[key]
        if data?
            data = JSON.parse(data)
            @cards = {}
            for k, v of data.cards
                @cards[k] = parseInt(v)
            @current_influence = parseInt(data.current_influence)
            @identity = if data.identity? then @all_cards[data.identity] else undefined
            @faction = data.faction
            @size = parseInt(data.size)
            @agenda_points = data.agenda_points
            @modified = false
            $(document).trigger('on_deck_loaded', [@side, @cards, @identity, name])
    
    delete: (name) ->
        key = "deck:#{name}"
        decks_key = "#{@side}:decks"
        decks = localStorage[decks_key]
        decks = JSON.parse(decks)
        delete decks[name]
        localStorage[decks_key] = JSON.stringify(decks)
        delete localStorage[key]
        side_name = $("#{@side}_name")[0]
        if side_name? and name is side_name.value
            @modified = true
        $(document).trigger('on_deck_deleted', [@side, name])

class CorpDeck extends BaseDeck
    constructor: (cards) ->
        @side = 'Corp'
        @agenda_points = 0
        super cards

    clear: () ->
        @agenda_points = 0
        super
    
    getAgendaPoints: -> return @agenda_points
    
    removeInvalidAgendas: ->
        for card_id, card_count of @cards
            card = @all_cards[card_id]
            if card.type is 'Agenda' and card.faction isnt @faction and card.faction isnt 'Neutral'
                @size -= card_count
                for i in [card_count-1..0]
                    $(document).trigger('on_card_removed', card)
                @agenda_points -= card.agenda_points * card_count
                delete @cards[card_id]
    
    removeInvalidCards: ->
        if @identity? and @identity.card_id is '03002' #engineered for success
            for card_id, card_count of @cards
                card = @all_cards[card_id]
                if card.faction is 'Jinteki'
                    @size -= card_count
                    for i in [card_count-1..0]
                        $(document).trigger('on_card_removed', card)
                    delete @cards[card_id]
    
    getAgendaPointLimit: ->
        return Math.floor(Math.max(@size, @getDeckSizeLimit())/5)*2 + 2

    validateDeck: ->
        invalid_properties = super
        min_agenda_points = @getAgendaPointLimit()
        if not(min_agenda_points <= @agenda_points <= min_agenda_points + 1)
            invalid_properties.push('getAgendaPoints')
        return invalid_properties

class RunnerDeck extends BaseDeck
    constructor: (cards) ->
        @side = 'Runner'
        super cards
    
    removeInvalidAgendas: ->
        return

    removeInvalidCards: ->
        return
    
    validateDeck: ->
        super
