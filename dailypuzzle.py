#!/usr/bin/env python3
import chess
import chess.pgn
import io
import json
import os
import time
import urllib.request

OUT = "/var/www/aryanmustafa/api/dailypuzzle"
INTERVAL = 3600  # check every hour; Lichess updates once per day

os.makedirs(os.path.dirname(OUT), exist_ok=True)

while True:
    try:
        req = urllib.request.Request(
            "https://lichess.org/api/puzzle/daily",
            headers={"Accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = json.loads(r.read())

        puzzle = raw["puzzle"]
        game   = raw["game"]

        # Lichess returns the full game PGN; the puzzle starts at initialPly.
        # Replay up to that ply with python-chess to get the exact FEN.
        pgn_text    = game["pgn"]
        initial_ply = puzzle["initialPly"]

        parsed = chess.pgn.read_game(io.StringIO(pgn_text))
        board  = parsed.board()
        for i, move in enumerate(parsed.mainline_moves()):
            board.push(move)
            if i >= initial_ply:
                break

        result = {
            "id":       puzzle["id"],
            "fen":      board.fen(),
            "side":     "white" if board.turn == chess.WHITE else "black",
            "solution": puzzle["solution"],   # UCI list e.g. ["e2e4","d7d5"]
            "rating":   puzzle.get("rating"),
            "themes":   puzzle.get("themes", []),
            "url":      f"https://lichess.org/training/{puzzle['id']}",
        }

        tmp = OUT + ".tmp"
        with open(tmp, "w") as f:
            json.dump(result, f)
        os.replace(tmp, OUT)  # atomic write

        print(f"updated: puzzle {result['id']}", flush=True)

    except Exception as e:
        print(f"error: {e}", flush=True)

    time.sleep(INTERVAL)
