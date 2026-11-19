# Decoding terminal input: keys, and SGR (1006) mouse reports.

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

const Event = Union{KeyEvent,MouseEvent,PasteEvent}

const SHIFT, ALT, CTRL = 1, 2, 4

function wait_bytes(io::IO, timeout::Float64)
    bytesavailable(io) > 0 && return true
    # Asking whether the input has ended waits for the next byte without taking it. Once the
    # input has ended there is nothing more to wait for.
    ended = Ref(false)
    return within(() -> ended[] = eof(io), timeout) && !ended[]
end

# The modifier parameter of a CSI sequence is 1 + (shift | alt<<1 | ctrl<<2).
csi_mods(params) = length(params) >= 2 ? max(params[2] - 1, 0) & 7 : 0

const CSI_KEYS = Dict('A' => :up, 'B' => :down, 'C' => :right, 'D' => :left,
                      'H' => :home, 'F' => :end, 'Z' => :backtab,
                      'P' => :f1, 'Q' => :f2, 'R' => :f3, 'S' => :f4)

const TILDE_KEYS = Dict(1 => :home, 7 => :home, 4 => :end, 8 => :end, 2 => :insert,
                        3 => :delete, 5 => :pageup, 6 => :pagedown, 11 => :f1)

"""
    read_event(io) -> Union{Event, Nothing}

Read one input event. Returns `nothing` for input that means nothing to the browser,
such as a terminal's reply to a query.
"""
function read_event(io::IO)
    c = read(io, Char)
    return c == '\e' ? read_escape(io) : decode_char(c)
end

# What follows an Escape.
function read_escape(io::IO)
    wait_bytes(io, 0.03) || return KeyEvent(:escape)
    c2 = read(io, Char)
    # A terminal sends a whole sequence at once. With nothing after it, this is Alt and a key.
    if c2 in "[O]P" && wait_bytes(io, 0.03)
        c2 == '[' && return read_csi(io)
        c2 == 'O' && return read_ss3(io)
        return skip_string(io)
    end
    if c2 == '\e'
        # Some terminals send Alt and an arrow as Escape before the arrow's own sequence.
        ev = read_escape(io)
        return ev isa KeyEvent && ev.key !== :escape ? with_alt(ev) : ev
    end
    return with_alt(decode_char(c2))
end

with_alt(ev::KeyEvent) = KeyEvent(ev.key, ev.char, ev.mods | ALT)
with_alt(ev) = ev

function decode_char(c::Char)
    c == '\r' || c == '\n' ? KeyEvent(:enter) :
    c == '\t' ? KeyEvent(:tab) :
    c == '\x7f' || c == '\b' ? KeyEvent(:backspace) :
    c < ' ' ? KeyEvent(Char(UInt32(c) + 0x60), CTRL) :
    KeyEvent(c)
end

function read_ss3(io::IO)
    c = read(io, Char)
    key = get(CSI_KEYS, c, nothing)
    return key === nothing ? nothing : KeyEvent(key)
end

# OSC and DCS strings (such as replies to colour queries) end with BEL or ESC \.
function skip_string(io::IO)
    while true
        # Give up if the string stops, so that it cannot swallow what is typed next.
        wait_bytes(io, 0.1) || return nothing
        c = read(io, Char)
        c == '\a' && return nothing
        if c == '\e'
            wait_bytes(io, 0.03) || return nothing
            read(io, Char) == '\\' && return nothing
        end
    end
end

function read_csi(io::IO)
    private = '\0'
    c = read(io, Char)
    if c in "<=>?"
        private = c
        c = read(io, Char)
    end
    buf = IOBuffer()
    while !('@' <= c <= '~')
        write(buf, c)
        c = read(io, Char)
    end
    final = c
    body = String(take!(buf))
    params = Int[something(tryparse(Int, p), 0) for p in split(body, ';'; keepempty=true)]
    if private == '<' && final in ('M', 'm')
        return mouse_event(params, final == 'M')
    end
    private == '\0' || return nothing
    if final == '~'
        isempty(params) && return nothing
        params[1] == 200 && return read_paste(io)
        key = get(TILDE_KEYS, params[1], nothing)
        return key === nothing ? nothing : KeyEvent(key, csi_mods(params))
    end
    final in ('I', 'O') && return nothing # focus in and out
    key = get(CSI_KEYS, final, nothing)
    key === nothing && return nothing
    return KeyEvent(key, key === :backtab ? SHIFT : csi_mods(params))
end

function mouse_event(params::Vector{Int}, pressed::Bool)
    length(params) == 3 || return nothing
    b, col, row = params
    mods = ((b & 4) != 0 ? SHIFT : 0) | ((b & 8) != 0 ? ALT : 0) | ((b & 16) != 0 ? CTRL : 0)
    button = b & 3
    if (b & 64) != 0
        action = button == 0 ? :wheelup : button == 1 ? :wheeldown : :wheelside
        return MouseEvent(action, 0, row, col, mods)
    elseif (b & 128) != 0
        return MouseEvent(pressed ? :press : :release, button + 8, row, col, mods)
    elseif (b & 32) != 0
        return MouseEvent(button == 3 ? :move : :drag, button + 1, row, col, mods)
    end
    return MouseEvent(pressed ? :press : :release, button + 1, row, col, mods)
end

# If the marker that ends a paste is lost, the paste ends when the terminal stops sending.
# Waiting for the marker would take every later key as part of the paste.
function read_paste(io::IO, timeout::Float64=1.0)
    marker = codeunits("\e[201~")
    bytes = UInt8[]
    while wait_bytes(io, timeout)
        push!(bytes, read(io, UInt8))
        n = length(bytes) - length(marker)
        n >= 0 && view(bytes, n+1:length(bytes)) == marker && return PasteEvent(String(resize!(bytes, n)))
    end
    return PasteEvent(String(bytes))
end
