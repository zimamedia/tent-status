Marbles.Views.NewPostForm = class NewPostFormView extends TentStatus.View
  @template_name: '_new_post_form'
  @view_name: 'new_post_form'

  constructor: ->
    super

    @elements = {}
    @text = {}

    post = new TentStatus.Models.Post entity: TentStatus.config.current_entity.toString()
    @post_cid = post.cid

    @on 'ready', => @ready = true
    @on 'ready', @init

    @render() unless @is_reply_form

  post: =>
    TentStatus.Models.Post.instances.all[@post_cid]

  context: =>
    _.extend {}, super,
      post: @post()
      max_chars: TentStatus.config.MAX_LENGTH

  init: =>
    @elements.submit = Marbles.DOM.querySelector('input[type=submit]', @el)
    @elements.errors = Marbles.DOM.querySelector('[data-errors_container]', @el)
    @elements.form = Marbles.DOM.querySelector('form', @el)
    @elements.textarea = Marbles.DOM.querySelector('textarea', @el)

    @text.disable_with = Marbles.DOM.attr(@elements.submit, 'data-disable_with')

    @initCharCounter()
    @initValidation()
    @initHotkeys()

    Marbles.DOM.on(@elements.form, 'submit', @submitWithValidation)

  initHotkeys: =>
    ## cmd/ctr enter to submit
    Marbles.DOM.on @elements.textarea, 'keydown', (e) =>
      if (e.metaKey || e.ctrlKey) && e.keyCode == 13
        e.preventDefault()
        @submitWithValidation()
        false
      else
        true

  initCharCounter: =>
    @elements.char_counter = Marbles.DOM.querySelector('.char-limit', @el)
    @max_chars = TentStatus.config.MAX_LENGTH

    Marbles.DOM.on @elements.textarea, 'keydown', (e) =>
      clearTimeout @_updateCharCounterTimeout
      return true if @frozen
      setTimeout @updateCharCounter, 20
      true

  initValidation: =>
    Marbles.DOM.on @elements.textarea, 'keyup', (e) =>
      clearTimeout @_validateTimeout
      return if @frozen
      setTimeout @validate, 300

      @updateCharCounter()

      null

    @updateCharCounter()

  submitWithValidation: (e) =>
    e?.preventDefault()
    data = @buildPostAttributes()
    @submit(data) if @validate(data, {validate_empty:true})

    null

  submit: (data) =>
    @disableWith(@text.disable_with)
    data ?= @buildPostAttributes()
    TentStatus.Models.Post.create(data,
      error: (res, xhr) =>
        @enable()
        @showErrors([{ text: "Error: #{JSON.parse(xhr.responseText)?.error}" }])

      success: (post, xhr) =>
        @enable()
        @render()
        @hide?()
    )

  disableWith: (text) =>
    @disable()
    @elements.submit.enable_with = @elements.submit.value
    @elements.submit.value = text

  disable: =>
    @frozen = true
    @elements.submit.disabled = true

  enable: =>
    @frozen = false
    @elements.submit.disabled = false
    if text = @elements.submit.enable_with
      @elements.submit.value = text
      delete @elements.submit.enable_with

  validate: (data, options = {}) =>
    return if @frozen
    data ?= @buildPostAttributes()
    errors = TentStatus.Models.Post.validate(data, options)
    @clearErrors()
    @showErrors(errors) if errors

    !errors

  clearErrors: =>
    for el in Marbles.DOM.querySelectorAll('.error', @el)
      Marbles.DOM.removeClass(el, 'error')
    Marbles.DOM.hide(@elements.errors)

  showErrors: (errors) =>
    error_messages = []
    for err in errors
      for name, msg of err
        input = Marbles.DOM.querySelector("[name=#{name}]", @el)
        Marbles.DOM.addClass(input, 'error')
        error_messages.push(msg)
    @elements.errors.innerHTML = error_messages.join("<br/>")
    Marbles.DOM.show(@elements.errors)

  updateCharCounter: =>
    return if @frozen
    char_count = @elements.textarea.value?.length || 0
    delta = @max_chars - char_count

    @elements.char_counter.innerText = delta

    if delta < 0
      # limit exceeded
      Marbles.DOM.addClass(@elements.char_counter, 'alert-error')
      @elements.submit.disabled = true
    else
      if delta == @max_chars
        # textarea empty
        @elements.submit.disabled = true
      else
        @elements.submit.disabled = false
      Marbles.DOM.removeClass(@elements.char_counter, 'alert-error')

  buildPostAttributes: =>
    attrs = Marbles.DOM.serializeForm(@elements.form)
    @buildPostMentionsAttributes(attrs)
    @buildPostPermissionsAttributes(attrs)
    attrs = _.extend attrs, {
      type: TentStatus.config.POST_TYPES.STATUS
    }
    attrs.content = { text: attrs.text }
    delete attrs.text
    attrs

  buildPostMentionsAttributes: (attrs) =>
    return unless attrs.text

    mentions = _.compact (_.map _.flatten(Array attrs.mentions), (entity) ->
      return unless entity
      { entity: entity }
    )
    delete attrs.mentions

    for i in TentStatus.Helpers.extractMentionsWithIndices(attrs.text)
      mentions.push { entity: i.entity }

    # in reply to mention
    if attrs.mentions_post_entity && attrs.mentions_post_id
      existing = false
      for m in mentions
        if m.entity == attrs.mentions_post_entity
          existing = true
          m.post = attrs.mentions_post_id
          break
      unless existing
        mentions.push { entity: attrs.mentions_post_entity, post: attrs.mentions_post_id }
        delete attrs.mentions_post_entity
        delete attrs.mentions_post_id

    attrs.mentions = mentions if mentions.length

  buildPostPermissionsAttributes: (attrs) =>
    permissions_view_cid = @_child_views.PermissionsFields?[0]
    if permissions_view_cid && (permissions_view = TentStatus.View.instances.all[permissions_view_cid])
      attrs.permissions = permissions_view.buildPermissions()
    else
      attrs.permissions = {
        public: true
      }

