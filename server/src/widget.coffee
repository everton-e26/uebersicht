exec     = require('child_process').exec
toSource = require('tosource')
stylus   = require('stylus')
nib      = require('nib')

# This is a wrapper (something like a base class), around the
# specific implementation of a widget.
# A widgets mostly lives client side, in the DOM. However, the
# backend also initializes widgets and runs widgets commands.
module.exports = (implementation) ->
  api = {}

  el        = null
  cssId     = null
  contentEl = null
  timer     = null
  started   = false
  rendered  = false
  childProc = null

  defaultStyle = 'top: 30px; left: 10px'

  # throws errors
  init = ->
    if (issues = validate(implementation)).length != 0
      throw new Error(issues.join(', '))

    api[k] = v for k, v of implementation

    cssId = api.id.replace(/\s/g, '_space_')
    unless implementation.css? or window? # we are client side
      implementation.css = parseStyle(implementation.style ? defaultStyle)
      delete implementation.style

    api

  # defaults
  api.id = 'widget'

  api.refreshFrequency = 1000

  api.render = (output) -> output

  api.afterRender = ->

  # renders and returns the widget's dom element
  api.create  = ->
    el        = document.createElement 'div'
    contentEl = document.createElement 'div'
    contentEl.id        = cssId
    contentEl.className = 'widget'
    el.innerHTML = "<style>#{implementation.css}</style>\n"
    el.appendChild(contentEl)
    el

  api.destroy = ->
    api.stop()
    return unless el?
    el.parentNode.removeChild(el)
    el = null
    contentEl = null

  # starts the widget refresh cycle
  api.start = ->
    started = true
    clearTimeout timer if timer?
    refresh()

  api.stop = ->
    started  = false
    rendered = false
    clearTimeout timer if timer?

  # runs the widget command. This happens server side
  api.exec = (options, callback) ->
    childProc.kill "SIGKILL" if childProc?
    childProc = exec api.command, options, (err, stdout, stderr) ->
      callback(err, stdout, stderr)
      childProc = null

  api.domEl = -> el

  # used by the backend to send a serialized version of the
  # widget to the client. JSON wont't work here, because we
  # need functions as well
  api.serialize = ->
    toSource implementation

  redraw = (output, error) ->
    if error
      contentEl.innerHTML = error
      console.error "#{api.id}:", error
      return rendered = false

    try
      renderOutput output
    catch e
      contentEl.innerHTML = e.message
      console.error errorToString(e)

  renderOutput = (output) ->
    if api.update? and rendered
      api.update(output, contentEl)
    else
      contentEl.innerHTML = api.render(output)
      loadScripts(contentEl)

      api.afterRender(contentEl)
      rendered = true
      api.update(output, contentEl) if api.update?

  loadScripts = (domEl) ->
    for script in domEl.getElementsByTagName('script')
      s = document.createElement('script')
      s.src = script.src
      domEl.replaceChild s, script

  refresh = ->
    return redraw() unless api.command?
    url = "/widgets/#{api.id}?cachebuster=#{new Date().getTime()}"

    $.ajax(url: url, timeout: api.refreshFrequency)
      .done((response) -> redraw(response) if started )
      .fail((response) -> redraw(null, response.responseText) if started)
      .always ->
        return unless started
        return if api.refreshFrequency == false
        timer = setTimeout refresh, api.refreshFrequency

  parseStyle = (style) ->
    return "" unless style

    scopedStyle = "##{cssId}\n  " + style.replace(/\n/g, "\n  ")
    stylus(scopedStyle)
      .import('nib')
      .use(nib())
      .render()

  validate = (impl) ->
    issues = []
    return ['empty implementation'] unless impl?
    if not impl.command? and impl.refreshFrequency != false
      issues.push 'no command given'
    issues

  errorToString = (err) ->
    str = "[#{api.id}] #{err.toString?() or err.message}"
    str += "\n  in #{err.stack.split('\n')[0]}()" if err.stack
    str

  init()
