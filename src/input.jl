# Terminal input, as the browser's events. TermInput reads the terminal; its events are made
# into these, which name keys and count mouse buttons from 1, as X11 does.

"""
    KeyEvent(key, char, mods)

`key` is `:char` (with `char` set) or a named key such as `:up`, `:enter` or `:pageup`.
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
read_event(io::IO) = browser_event(TermInput.readevent(io))

browser_event(ev::TermInput.KeyEvent) = key_event(ev.code)
browser_event(ev::TermInput.PasteEvent) = PasteEvent(ev.text)
function browser_event(ev::TermInput.MouseEvent)
    ev.kind in (:wheelup, :wheeldown) && return MouseEvent(ev.kind, 0, ev.y, ev.x, ev.mods)
    # back and forward are 8 and 9
    button = ev.button >= 128 ? ev.button - 120 : ev.button + 1
    return MouseEvent(ev.kind, button, ev.y, ev.x, ev.mods)
end
browser_event(ev::TermInput.SchemeEvent) = SchemeEvent(ev.dark, ev.bg)
browser_event(::TermInput.LegacyMouseEvent) = LegacyMouseEvent()
# the terminal's focus
browser_event(ev) = nothing

const NAMED_KEYS = Dict(
    K_LEFT => (:left, 0), K_RIGHT => (:right, 0), K_UP => (:up, 0), K_DOWN => (:down, 0),
    K_HOME => (:home, 0), K_END => (:end, 0), K_PGUP => (:pageup, 0), K_PGDN => (:pagedown, 0),
    K_DEL => (:delete, 0), K_STAB => (:backtab, SHIFT), K_SUP => (:up, SHIFT),
    K_SDOWN => (:down, SHIFT), K_WORD_BACK => (:backspace, ALT),
    # Alt and an arrow, or Alt-b and Alt-f, which TermInput reads as moving by a word
    K_WORD_LEFT => (:left, ALT), K_WORD_RIGHT => (:right, ALT))

function key_event(k::Int)
    named = get(NAMED_KEYS, k, nothing)
    named === nothing || return KeyEvent(named...)
    k == K_WORD_KILL && return KeyEvent('d', ALT)
    k == K_EDIT && return KeyEvent('e', ALT)
    k == 27 && return KeyEvent(:escape)
    (k < 0 || k >= K_BASE) && return nothing
    return decode_char(keychar(k))
end

function decode_char(c::Char)
    c == '\r' || c == '\n' ? KeyEvent(:enter) :
    c == '\t' ? KeyEvent(:tab) :
    c == '\x7f' || c == '\b' ? KeyEvent(:backspace) :
    c < ' ' ? KeyEvent(Char(UInt32(c) + 0x60), CTRL) :
    KeyEvent(c)
end
