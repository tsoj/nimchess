import unittest
import nimchess/[game, strchess, movegen]

suite "Game Tests":
  test "basic game creation":
    let game1 = newGame(
      event = "Test Tournament", site = "Test City", white = "Alice", black = "Bob"
    )

    check game1.headers["Event"] == "Test Tournament"
    check game1.headers["Site"] == "Test City"
    check game1.headers["White"] == "Alice"
    check game1.headers["Black"] == "Bob"
    check "SetUp" notin game1.headers
    check game1.result == "*"

  test "move addition":
    var game1 = newGame(
      event = "Test Tournament", site = "Test City", white = "Alice", black = "Bob"
    )

    game1.addMove("e4".toMove(game1.currentPosition))
    check game1.currentPosition ==
      "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1".toPosition

    game1.addMove("e5".toMove(game1.currentPosition))
    check game1.currentPosition ==
      "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2".toPosition

    check game1.moves.len == 2
    check game1.result == "*"

  test "illegal move detection":
    var game1 = newGame()
    game1.addMove("e4".toMove(game1.currentPosition))

    expect(ValueError):
      game1.addMove("e4".toMove(game1.currentPosition)) # e4 already played

  test "Scholar's mate":
    var mateGame = newGame()

    mateGame.addMove("e4".toMove(mateGame.currentPosition))
    mateGame.addMove("e5".toMove(mateGame.currentPosition))
    mateGame.addMove("Bc4".toMove(mateGame.currentPosition))
    mateGame.addMove("Nc6".toMove(mateGame.currentPosition))
    mateGame.addMove("Qh5".toMove(mateGame.currentPosition))
    mateGame.addMove("Nf6".toMove(mateGame.currentPosition))
    mateGame.addMove("Qxf7#".toMove(mateGame.currentPosition))

    check mateGame.currentPosition.isMate()
    # Note: The result field behavior may depend on implementation details

  test "repetition detection":
    var repGame = newGame()

    check repGame.repetitionCount() == 1

    repGame.addMove("Nf3".toMove(repGame.currentPosition))
    repGame.addMove("Nf6".toMove(repGame.currentPosition))
    repGame.addMove("Ng1".toMove(repGame.currentPosition))
    repGame.addMove("Ng8".toMove(repGame.currentPosition))

    check repGame.repetitionCount() == 2
    check repGame.repetitionCount(-2) == 1

    repGame.addMove("Nf3".toMove(repGame.currentPosition))
    repGame.addMove("Nf6".toMove(repGame.currentPosition))
    repGame.addMove("Ng1".toMove(repGame.currentPosition))
    repGame.addMove("Ng8".toMove(repGame.currentPosition))

    for i in 0 .. 8:
      check repGame.repetitionCount(i) == 1 + i div 4

    check repGame.repetitionCount(9) == 0
    check repGame.hasRepetition()

  test "FEN starting position":
    let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    let fenGame = newGame(fen = fen)

    check fenGame.headers.getOrDefault("SetUp", "not set") == "1"
    check fenGame.headers.getOrDefault("FEN", "not set") == fen

  test "game creation with default parameters":
    let defaultGame = newGame()

    check defaultGame.result == "*"
    check defaultGame.moves.len == 0
    check defaultGame.currentPosition == classicalStartPos
