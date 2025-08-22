import nimchess/[bitboard, engine, game, move, movegen, pgn, position, strchess, types]
export bitboard, engine, game, move, movegen, pgn, position, strchess, types
## ========
## nimchess
## ========
##
## A chess library that provides fast move generation,
## position manipulation, and support for common chess formats like FEN and PGN.
## The library uses bitboards for efficient board representation and move generation.
##
## `GitHub <https://github.com/tsoj/nimchess>`_
##
## Overview
## ========
##
## The library is organized into several core modules:
##
## Core Types and Board Representation
## -----------------------------------
##
## - `types <nimchess/types.html>`_: Fundamental chess types (Square, Color, Piece)
## - `bitboard <nimchess/bitboard.html>`_: Efficient bitboard operations for fast computation
## - `position <nimchess/position.html>`_: Chess position representation and manipulation
##
## Move Generation and Validation
## ------------------------------
##
## - `move <nimchess/move.html>`_: Move representation and basic operations
## - `movegen <nimchess/movegen.html>`_: Fast legal move generation
##
## Game Management and Formats
## ---------------------------
##
## - `game <nimchess/game.html>`_: Complete chess game representation
## - `pgn <nimchess/pgn.html>`_: PGN (Portable Game Notation) reading and writing
## - `strchess <nimchess/strchess.html>`_: String parsing utilities (FEN, SAN, UCI)
##
## Engine Communication
## --------------------
##
## - `engine <nimchess/engine.html>`_: UCI chess engine communication and analysis
##
## Quick Start
## ===========
##
## Creating and working with positions:
##
runnableExamples:
  # Create starting position from FEN
  let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

  # Display the position
  echo pos # Shows board with Unicode pieces

  # Generate all legal moves
  for move in pos.legalMoves:
    echo move.toSAN(pos) # Show move in algebraic notation

  # Make a move
  let newPos = pos.doMove("e4".toMove(pos))
  echo newPos.fen() # Get FEN string of new position
##
## Working with games and PGN:
##
runnableExamples:
  let games = readPgnFile("tests/testdata/pgns.pgn")
  for game in games:
    echo game.headers.getOrDefault("Event", "?")
    echo "Result: ", game.result
##
## Working with bitboards:
##
runnableExamples:
  let
    position =
      "1rbn1rk1/p2p2q1/1p2p1pp/2b5/2P1NP2/P3P3/1P2BNP1/1KQR3R b - - 4 21".toPosition
    bishopAttack = position.attacksFrom(bishop, c5)
    attackedPawns = position[white, pawn] and bishopAttack

  echo attackedPawns

  for attackedPawnSquare in attackedPawns:
    echo attackedPawnSquare
##
## Working with chess engines:
##
runnableExamples:
  # Note: This example requires a UCI engine like Stockfish to be installed
  var engine = newUciEngine("stockfish")

  let startPos = classicalStartPos
  let limit = Limit(depth: 10)

  let result = engine.play(startPos, limit)

  echo "Best move: ", result.move.toSAN(startPos)
  if result.info.score.isSome:
    echo "Evaluation: ", result.info.score.get
