# nimchess

A fast and efficient chess library for Nim, with move generation, move validation, and support for common chess formats.

[Docs](https://tsoj.github.io/nimchess/)

## Installation

Add nimchess to your `.nimble` file:

```nim
requires "nimchess >= 0.1.0"
```

Or install directly:

```
nimble install nimchess
```

## Features

- Fast move generation using bitboards
- FEN parsing and generation
- PGN reading and writing with SAN notation support
- Chess960 (Fischer Random) support

## Quick Examples

### Creating Positions

```nim
# Starting position
let startPos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

# From Chess960 FEN string
let frcPos = "rnbqkbrn/p1pp1pp1/4p3/7p/2p4P/2P5/PP1PPPP1/R1BQKBRN w QGqg - 0 9".toPosition
```

### Working with Moves

```nim
# Create move from UCI or SAN notation
let move = "Nf3".toMove(position)

# Check if move is legal and make a move
if position.isLegal(move):
  let newPos = position.doMove(move)

# Get all legal moves of a position
for move in position.legalMoves:
  echo move
```

### PGN Support

```nim
# Read PGN file
let game = readPgnFile("game.pgn")[0]
echo game.headers["White"]
echo game.headers["Black"]
echo game.result
```

### Position Display

```nim
# Print position
echo position  # Shows board with Unicode pieces

# Get FEN string
echo position.fen()
```

## Requirements

- Nim >= 2.2.4

## License

LGPL-3.0 with linking exception

## Author

Jost Triller
