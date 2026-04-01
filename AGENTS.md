# Repository Guidelines

nimchess: A fast and efficient chess library for Nim, with move generation and support for common chess formats.

## Project Structure & Module Organization
├── src/
│   ├──nimchess/
│   │   ├── types.nim    # Fundamental chess types: Square, Color, Piece, ColoredPiece
│   │   ├── bitboard.nim # Bitboard operations & attack tables
│   │   ├── castling.nim # Castling validation & target squares
│   │   ├── position.nim # Chess position state: piece placement, castling rights, en passant, side to move, move counters
│   │   ├── move.nim     # Move encoding, `doMove`, `isLegal`
│   │   ├── movegen.nim  # Move generation, `legalMoves`, `isMate`
│   │   ├── strchess.nim # FEN, SAN, UCI parsing/formatting
│   │   ├── game.nim     # Game representation & history
│   │   ├── pgn.nim      # PGN file I/O
│   │   ├── engine.nim   # UCI engine communication
│   │   └── perft.nim    # Move generation verification
│   └── nimchess.nim     # Main library export module
└── tests/

## Test, and Development Commands
- Test for compilation errors of single files: `nim check src/nimchess/somefile.nim`.
- Run all tests: `nimble test -d:release -d:maxNumPerftNodes=100000`.
- Run specific test with: `nim r -d:release tests/test_sometest.nim`

## Coding Style & Naming Conventions
- Language: Nim 2.x (`requires "nim >= 2.0.0"`).
- Format files with `nph ./`. For cases where the code looks much better in a specific format, use `#!fmt: off` and `#!fmt: on` to disable and enable nph formatting.
- Naming: types `CamelCase`, procs/vars `camelCase`, modules lowercased without underscore (e.g., `parserequires.nim`), except for test modules (e.g., `test_parserequires.nim`).
