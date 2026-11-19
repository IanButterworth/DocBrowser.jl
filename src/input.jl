# Terminal input, as the browser's events. `REPL.TerminalMenus` reads the terminal, and its
# events become these, which the browser's handlers were written for.

"""
    KeyEvent(key, char, mods)

`key` is `:char` (with `char` set) or a named key such as `:up`, `:enter` or `:f1`.
`mods` is a bit set: 1 shift, 2 alt, 4 ctrl.
"""
struct KeyEvent
    key::Symbol
    char::Char
    mods::Int
end
KeyEvent(key::Symbol, mods::Int=0) = KeyEvent(key, '\0', mods)
KeyEvent(c::Char, mods::Int=0) = KeyEvent(:char, c, mods)

"""
    MouseEvent(action, button, row, col, mods)

`action` is `:press`, `:release`, `:drag`, `:move`, `:wheelup` or `:wheeldown`.
"""
struct MouseEvent
    action::Symbol
    button::Int
    row::Int
    col::Int
    mods::Int
end

struct PasteEvent
    text::String
end

"""
    SchemeEvent(dark, background)

The terminal said whether it is dark (`dark`, or `nothing` when it did not say) or what its
background colour is (`background`, as it spelled it, or `""`), in answer to the browser's
questions or when its scheme changes.
"""
struct SchemeEvent
    dark::Union{Nothing,Bool}
    background::String
end

"""
    LegacyMouseEvent()

A mouse report in the X10 encoding, which the browser does not ask for. It means the terminal
lost the SGR encoding while still reporting, as VS Code's does when it reattaches a session.
"""
struct LegacyMouseEvent end

const Event = Union{KeyEvent,MouseEvent,PasteEvent,SchemeEvent,LegacyMouseEvent}

const SHIFT, ALT, CTRL = 1, 2, 4

function wait_bytes(io::IO, timeout::Float64)
    bytesavailable(io) > 0 && return true
    # Asking whether the input has ended waits for the next byte without taking it. Once the
    # input has ended there is nothing more to wait for.
    ended = Ref(false)
    return within(() -> ended[] = eof(io), timeout) && !ended[]
end

"""
    read_event(io) -> Union{Event, Nothing}

Read one input event. Returns `nothing` for input that means nothing to the browser,
such as a terminal's reply to a query.
"""
read_event(io::IO) = browser_event(TM.readevent(io))

function browser_event(ev::TM.KeyEvent)
    ev.key isa Char && return KeyEvent(ev.key, ev.mods)
    ev.key === :tab && ev.mods & SHIFT != 0 && return KeyEvent(:backtab, ev.mods)
    return KeyEvent(ev.key, ev.mods)
end
function browser_event(ev::TM.MouseEvent)
    action = ev.action in (:wheelleft, :wheelright) ? :wheelside : ev.action
    return MouseEvent(action, ev.button, ev.row, ev.col, ev.mods)
end
browser_event(ev::TM.PasteEvent) = PasteEvent(ev.text)
browser_event(ev::TM.SchemeEvent) = SchemeEvent(ev.dark, ev.background)
browser_event(::TM.LegacyMouseEvent) = LegacyMouseEvent()
browser_event(::Union{TM.FocusEvent,Nothing}) = nothing

# A key as the line field takes it.
term_key(ev::KeyEvent) = TM.KeyEvent(ev.key === :char ? ev.char : ev.key === :backtab ? :tab : ev.key, ev.mods)
