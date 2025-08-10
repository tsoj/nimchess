## nimchess - A fast and efficient chess library for Nim
## =====================================================
##
## nimchess is a chess library that provides fast move generation,
## position manipulation, and support for common chess formats like FEN and PGN.
## The library uses bitboards for efficient board representation and move generation.
##
## Overview
## --------
##
## The library is organized into several core modules:
##
## Core Types and Board Representation
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##
## - `types <nimchess/types.html>`_: Fundamental chess types (Square, Color, Piece)
## - `bitboard <nimchess/bitboard.html>`_: Efficient bitboard operations for fast computation
## - `position <nimchess/position.html>`_: Chess position representation and manipulation
##
## Move Generation and Validation
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##
## - `move <nimchess/move.html>`_: Move representation and basic operations
## - `movegen <nimchess/movegen.html>`_: Fast legal move generation
##
## Game Management and Formats
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~
##
## - `game <nimchess/game.html>`_: Complete chess game representation
## - `pgn <nimchess/pgn.html>`_: PGN (Portable Game Notation) reading and writing
## - `strchess <nimchess/strchess.html>`_: String parsing utilities (FEN, SAN, UCI)
##
## Quick Start
## -----------
##
## Creating and working with positions:
##
## ```nim
## import nimchess
##
## # Create starting position from FEN
## let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
##
## # Display the position
## echo pos  # Shows board with Unicode pieces
##
## # Generate all legal moves
## for move in pos.legalMoves:
##   echo move.toSAN(pos)  # Show move in algebraic notation
##
## # Make a move
## let newPos = pos.doMove("e4".toMove(pos))
## echo newPos.fen()  # Get FEN string of new position
## ```
##
## Working with games and PGN:
##
## ```nim
## import nimchess
##
## # Read a PGN file
## let games = readPgnFile("games.pgn")
## for game in games:
##   echo game.headers["White"], " vs ", game.headers["Black"]
##   echo "Result: ", game.result
## ```


import nimchess/[bitboard, game, move, movegen, pgn, position, strchess, types]
export bitboard, game, move, movegen, pgn, position, strchess, types
