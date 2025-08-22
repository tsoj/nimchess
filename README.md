# nimchess

A fast and efficient chess library for Nim, with move generation and support for common chess formats.

[Docs](https://tsoj.github.io/nimchess/)

## Installation

Add nimchess to your `.nimble` file:

```nim
requires "nimchess >= 0.1.4"
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
- UCI chess engine communication and analysis

## Quick Examples

### Creating Positions

```nim
import nimchess

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
let game = readPgnFile("game.pgn")[0]
echo game.headers["White"]
echo game.headers["Black"]
echo game.result
```

### Engine Communication

```nim
# Communicate with UCI engines like Stockfish
var engine = newUciEngine("stockfish")
let result = engine.play(startPos, Limit(depth: 10))
if result.move.isSome:
  echo "Best move: ", result.move.get.toSAN(startPos)
engine.close()
```

## Requirements

- Requires Nim >= 2.2.4
- Ideally compile with `-d:danger --cc:clang --passC:"-flto" --passL:"-flto"` for optimal performance

## License

LGPL-3.0 with linking exception

## Author

Jost Triller
