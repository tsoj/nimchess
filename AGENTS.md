# Repository Guidelines

nimchess: A fast and efficient chess library for Nim, with move generation and support for common chess formats.

## Project Structure & Module Organization
```
├── src/
│   ├── nimchess/
│   │   ├── types.nim    # Fundamental chess types: Square, Color, Piece, ColoredPiece
│   │   ├── bitboard.nim # Bitboard operations & attack tables
│   │   ├── castling.nim # Castling validation & target squares (internal, not exported)
│   │   ├── position.nim # Chess position state: piece placement, castling rights, en passant, side to move, move counters
│   │   ├── move.nim     # Move encoding, `doMove`, `isLegal`
│   │   ├── movegen.nim  # Move generation, `legalMoves`, `isMate`
│   │   ├── strchess.nim # FEN, SAN, UCI parsing/formatting
│   │   ├── game.nim     # Game representation & history
│   │   ├── pgn.nim      # PGN file I/O
│   │   ├── engine.nim   # UCI engine communication
│   │   └── perft.nim    # Move generation verification
│   └── nimchess.nim     # Main library export module
└── tests/               # Test files named test_<modulename>.nim
```

The public API is everything exported through `nimchess.nim`. `castling.nim` is internal and not exported.

## Dependencies

No external Nim dependencies — only the Nim stdlib is used. Do not add third-party packages.

## Test and Development Commands
- Test for compilation errors of single files: `nim check src/nimchess/somefile.nim`.
- Run all tests: `nimble test -d:release -d:maxNumPerftNodes=100000`.
- Run specific test with: `nim r -d:release tests/test_sometest.nim`
- Tests import `nimchess` (not individual submodules) via the path switch in `tests/config.nims`.
- The `-d:release` flag matters: perft tests are performance-sensitive.

## Coding Style & Naming Conventions
- Language: Nim (`requires "nim >= 2.2.4"`).
- Code is formatted with [nph](https://github.com/arnetheduck/nph). Do not manually reformat code that nph would handle. For cases where specific formatting is important, use `#!fmt: off` and `#!fmt: on` to disable/enable nph.
- Naming: types `CamelCase`, procs/vars `camelCase`, modules lowercased without underscore (e.g., `strchess.nim`), except for test modules (e.g., `test_fenparsing.nim`).

## Key Architecture & Types

- **Bitboard-centric**: Board representation uses `Bitboard` (`uint64`). `Position` stores pieces as `array[pawn..king, Bitboard]` and colors as `array[white..black, Bitboard]`.
- **`Move` is `distinct uint16`**: An opaque type — do not manipulate the bits directly. Use the provided functions to create moves (`newMove`) and query properties (`source`, `target`, `promoted`, `isCapture`, `isCastling`, `isNoMove`, etc.). An empty/zero move is given with the constant `noMove`.
- **`doMove` returns a new `Position`**: It is a functional/pure operation, not mutating. Do not expect in-place mutation.
- **`Square` is an enum** with `noSquare` sentinel. `ColoredPiece` is a case object discriminated on `piece` (with `noPiece` as the empty variant) — always match the discriminator correctly.

## Error Handling

- **`doAssert`** for internal invariants and library-misuse checks (always evaluated, even in release builds). Example: checking a square is occupied before querying its piece.
- **`assert`** for hot-path sanity checks that should be compiled out in release. Example: bounds checks in move encoding, pseudolegality checks in `doMove`.
- **Exceptions** for user-facing / input-facing errors (malformed FEN, illegal PGN, invalid engine state). Use only built-in Nim stdlib exception types (`ValueError`, `IOError`, `IndexDefect`, etc.); no custom exception classes.

## Performance

Performance matters in the core move generation and bitboard paths (move.nim, movegen.nim, bitboard.nim, position.nim). In these areas, prefer efficient code and avoid unnecessary allocations.

For non-hot-path code (FEN/PGN parsing, engine communication, string formatting), prefer simplicity and readability over performance-centric engineering. If fast performance comes naturally from simple code, great — but do not prematurely optimize these areas.
