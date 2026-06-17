#!/usr/bin/env bash
# chess.aryanmustafa.com/play — Daily Chess Puzzle
# Usage: curl -sL chess.aryanmustafa.com/play | bash

set -euo pipefail

API="https://aryanmustafa.com/api/dailypuzzle"

# ── Colours ────────────────────────────────────────────────────────────────────
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"

LIGHT_BG="${ESC}[48;5;229m"   # warm cream
DARK_BG="${ESC}[48;5;94m"     # brown

CHRISTMAS=false
for arg in "$@"; do
    case "$arg" in
        --christmas) CHRISTMAS=true ;;
    esac
done

if $CHRISTMAS; then
    WHITE_PIECE="${ESC}[1;92m"            # bold bright green
    BLACK_PIECE="${ESC}[1;91m"            # bold bright red
else
    WHITE_PIECE="${ESC}[1;38;5;208m"      # bold orange
    BLACK_PIECE="${ESC}[38;5;93m${ESC}[1m" # bold purple
fi

CYAN="${ESC}[36m"
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
DIM="${ESC}[2m"

# ── Helpers ────────────────────────────────────────────────────────────────────
die() { echo "${RED}Error: $*${RESET}" >&2; exit 1; }
require_cmd() { command -v "$1" &>/dev/null || die "'$1' is required but not installed."; }

require_cmd curl
require_cmd python3

# ── Fetch puzzle ───────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}${CYAN}  ♟  Daily Chess Puzzle${RESET}"
echo "${DIM}  Fetching from lichess via aryanmustafa.com…${RESET}"
echo ""

PUZZLE_JSON=$(curl -sf "$API") || die "Could not reach $API"

PUZZLE_ID=$(echo "$PUZZLE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])")
FEN=$(echo "$PUZZLE_JSON"       | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['fen'])")
SIDE=$(echo "$PUZZLE_JSON"      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['side'])")
RATING=$(echo "$PUZZLE_JSON"    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rating','?'))")
THEMES=$(echo "$PUZZLE_JSON"    | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.get('themes',[])))")
SOLUTION=$(echo "$PUZZLE_JSON"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d['solution']))")
URL=$(echo "$PUZZLE_JSON"       | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['url'])")

read -ra SOL_ALL <<< "$SOLUTION"
# solution[0] is the opponent's move that opens the puzzle (applied silently, shown on board)
# solution[1:] are the moves the player must find
SETUP_MOVE=""
SOL_ARRAY=("${SOL_ALL[@]}")
SOL_LEN=${#SOL_ARRAY[@]}

# ── Python board engine ────────────────────────────────────────────────────────
py_engine() {
    python3 - "$@" <<'PYEOF'
import sys

def parse_fen(fen):
    parts = fen.split()
    rows = parts[0].split('/')
    board = {}
    for r, row in enumerate(rows):
        c = 0
        for ch in row:
            if ch.isdigit():
                c += int(ch)
            else:
                board[(r, c)] = ch
                c += 1
    side = parts[1]
    return board, side

def board_to_str(board):
    lines = []
    for r in range(8):
        row = []
        for c in range(8):
            row.append(board.get((r, c), '.'))
        lines.append(''.join(row))
    return '\n'.join(lines)

def uci_to_coords(uci):
    fc, fr, tc, tr = uci[0], uci[1], uci[2], uci[3]
    return (8 - int(fr), ord(fc) - ord('a')), (8 - int(tr), ord(tc) - ord('a'))

def apply_move(board, uci):
    src, dst = uci_to_coords(uci)
    piece = board.get(src)
    if piece is None:
        return None, "No piece at source square"
    new_board = dict(board)
    if piece in ('K', 'k') and abs(src[1] - dst[1]) == 2:
        new_board[dst] = piece
        del new_board[src]
        if dst[1] == 6:
            rook_src, rook_dst = (src[0], 7), (src[0], 5)
        else:
            rook_src, rook_dst = (src[0], 0), (src[0], 3)
        rook = new_board.get(rook_src)
        if rook:
            new_board[rook_dst] = rook
            del new_board[rook_src]
    else:
        if piece in ('P', 'p') and src[1] != dst[1] and dst not in board:
            new_board.pop((src[0], dst[1]), None)
        new_board[dst] = piece
        del new_board[src]
        if len(uci) == 5:
            promo = uci[4]
            new_board[dst] = promo.upper() if piece.isupper() else promo.lower()
        elif piece == 'P' and dst[0] == 0:
            new_board[dst] = 'Q'
        elif piece == 'p' and dst[0] == 7:
            new_board[dst] = 'q'
    return new_board, None

def board_to_fen(board, side):
    rows = []
    for r in range(8):
        empty = 0
        row_str = ''
        for c in range(8):
            p = board.get((r, c))
            if p:
                if empty: row_str += str(empty); empty = 0
                row_str += p
            else:
                empty += 1
        if empty: row_str += str(empty)
        rows.append(row_str)
    new_side = 'b' if side == 'w' else 'w'
    return '/'.join(rows) + f' {new_side} - - 0 1'

def validate_uci(uci):
    uci = uci.strip().lower()
    if len(uci) not in (4, 5):
        return None, "Move must be 4-5 chars (e.g. e2e4)"
    if uci[0] not in 'abcdefgh' or uci[2] not in 'abcdefgh':
        return None, "Invalid file (use a-h)"
    if uci[1] not in '12345678' or uci[3] not in '12345678':
        return None, "Invalid rank (use 1-8)"
    if len(uci) == 5 and uci[4] not in 'qrbn':
        return None, "Invalid promotion piece (q/r/b/n)"
    return uci, None

cmd = sys.argv[1]

if cmd == "show":
    board, _ = parse_fen(sys.argv[2])
    print(board_to_str(board))

elif cmd == "apply":
    board, side = parse_fen(sys.argv[2])
    uci, err = validate_uci(sys.argv[3])
    if err:
        print(f"ERR:{err}"); sys.exit(0)
    new_board, err = apply_move(board, uci)
    if err:
        print(f"ERR:{err}"); sys.exit(0)
    print(board_to_fen(new_board, side))

elif cmd == "hint_piece":
    board, _ = parse_fen(sys.argv[2])
    src, _ = uci_to_coords(sys.argv[3])
    piece = board.get(src, '?')
    file_ = chr(ord('a') + src[1])
    rank_ = str(8 - src[0])
    print(f"{piece}@{file_}{rank_}")
PYEOF
}

# ── Draw board ─────────────────────────────────────────────────────────────────
draw_board() {
    local fen="$1"
    local board_str
    board_str=$(py_engine show "$fen")

    piece_char() {
        case "$1" in
            P|p) echo "P" ;; N|n) echo "N" ;; B|b) echo "B" ;;
            R|r) echo "R" ;; Q|q) echo "Q" ;; K|k) echo "K" ;;
            *) echo " " ;;
        esac
    }

    echo ""
    echo "    a   b   c   d   e   f   g   h"
    echo "  ┌───┬───┬───┬───┬───┬───┬───┬───┐"

    local row_idx=0
    while IFS= read -r row_line; do
        local rank=$((8 - row_idx))
        printf "%d │" "$rank"

        local col_idx=0
        while [ $col_idx -lt 8 ]; do
            local ch="${row_line:$col_idx:1}"
            local pc; pc=$(piece_char "$ch")

            local is_light=$(( (row_idx + col_idx) % 2 ))
            local sq_bg
            if [ "$is_light" -eq 0 ]; then
                sq_bg="$LIGHT_BG"
            else
                sq_bg="$DARK_BG"
            fi

            # White pieces = uppercase letters; black pieces = lowercase
            local fg
            if [[ "$ch" =~ [A-Z] ]]; then
                fg="$WHITE_PIECE"
            else
                fg="$BLACK_PIECE"
            fi

            printf "%s%s %s %s│" "$sq_bg" "$fg" "$pc" "$RESET"
            col_idx=$((col_idx + 1))
        done

        printf " %d\n" "$rank"
        if [ "$row_idx" -lt 7 ]; then
            echo "  ├───┼───┼───┼───┼───┼───┼───┼───┤"
        fi
        row_idx=$((row_idx + 1))
    done <<< "$board_str"

    echo "  └───┴───┴───┴───┴───┴───┴───┴───┘"
    echo "    a   b   c   d   e   f   g   h"
    echo ""
}

# ── Setup ──────────────────────────────────────────────────────────────────────
SIDE_DISPLAY=$(echo "$SIDE" | awk '{print toupper(substr($0,1,1))substr($0,2)}')

echo "  ${BOLD}Puzzle #${PUZZLE_ID}${RESET}   ${DIM}Rating: ${RATING}   Themes: ${THEMES}${RESET}"
echo "  ${DIM}${URL}${RESET}"
echo ""
echo "  ${YELLOW}${BOLD}${SIDE_DISPLAY} to move.${RESET}  Find the best sequence (${SOL_LEN} moves)."
echo "  ${DIM}Enter moves in UCI format (e.g. e2e4).  Type 'hint' or 'quit'.${RESET}"

# Apply opponent's opening move so the board shows the puzzle start position
current_fen="$FEN"
move_num=0

draw_board "$current_fen"

# ── Puzzle loop ────────────────────────────────────────────────────────────────
declare -A PIECE_NAMES=(
    [P]="Pawn" [N]="Knight" [B]="Bishop" [R]="Rook" [Q]="Queen" [K]="King"
    [p]="Pawn" [n]="Knight" [b]="Bishop" [r]="Rook" [q]="Queen" [k]="King"
)

while [ "$move_num" -lt "$SOL_LEN" ]; do
    expected="${SOL_ARRAY[$move_num]}"

    printf "  ${BOLD}Move %d/%d${RESET} › " "$((move_num + 1))" "$SOL_LEN"
    read -r user_input </dev/tty

    user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    case "$user_input" in
        quit|q|exit)
            echo ""
            echo "  ${DIM}Puzzle abandoned. Solution: ${SOLUTION}${RESET}"
            echo "  ${DIM}${URL}${RESET}"
            echo ""
            exit 0
            ;;
        hint|h)
            hint_raw=$(py_engine hint_piece "$current_fen" "$expected")
            piece_sym="${hint_raw%%@*}"
            sq="${hint_raw##*@}"
            full_name="${PIECE_NAMES[$piece_sym]:-Piece}"
            echo "  ${YELLOW}Hint: Move the ${full_name} on ${sq}.${RESET}"
            continue
            ;;
        "")
            continue
            ;;
    esac

    if ! [[ "$user_input" =~ ^[a-h][1-8][a-h][1-8][qrbn]?$ ]]; then
        echo "  ${RED}Invalid format. Use UCI notation, e.g. e2e4 or a7a8q.${RESET}"
        continue
    fi

    if [ "$user_input" = "$expected" ]; then
        move_num=$((move_num + 1))

        new_fen=$(py_engine apply "$current_fen" "$user_input")
        if [[ "$new_fen" == ERR:* ]]; then
            echo "  ${RED}${new_fen#ERR:}${RESET}"
            move_num=$((move_num - 1))
            continue
        fi
        current_fen="$new_fen"

        if [ "$move_num" -lt "$SOL_LEN" ]; then
            opp_move="${SOL_ARRAY[$move_num]}"
            echo "  ${GREEN}✓ Correct!${RESET}  ${DIM}Opponent plays ${opp_move}…${RESET}"
            new_fen=$(py_engine apply "$current_fen" "$opp_move")
            if [[ "$new_fen" != ERR:* ]]; then
                current_fen="$new_fen"
            fi
            move_num=$((move_num + 1))
            draw_board "$current_fen"
        else
            echo "  ${GREEN}✓ Correct!${RESET}"
            draw_board "$current_fen"
        fi
    else
        echo "  ${RED}✗ Not quite — try again.${RESET}"
    fi
done

echo ""
echo "  ${BOLD}${GREEN}Puzzle solved! ♟${RESET}"
echo "  ${DIM}Full solution: ${SOLUTION}${RESET}"
echo "  ${DIM}Review on Lichess: ${URL}${RESET}"
echo ""
