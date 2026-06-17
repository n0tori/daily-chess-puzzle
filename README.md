# Daily Chess Puzzle

Solve today's Lichess puzzle in your terminal.

Python script `dailypuzzle.py` runs as a systemd service, fetches the FEN sequence and solution from Lichess' API which an endpoint /api/dailypuzzle on my website serves.

## Usage
`curl -sL chess.aryanmustafa.com/play | bash`

## Requirements
1. curl
2. bash
3. python3
