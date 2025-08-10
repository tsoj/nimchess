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

    mateGame.addMove "e4"
    mateGame.addMove "e5"
    mateGame.addMove "Bc4"
    mateGame.addMove "Nc6"
    mateGame.addMove "Qh5"
    mateGame.addMove "Nf6"
    mateGame.addMove "Qxf7#"

    check mateGame.currentPosition.isMate()
    # Note: The result field behavior may depend on implementation details

  test "repetition detection":
    var repGame = newGame()

    check repGame.repetitionCount() == 1

    repGame.addMove "Nf3"
    repGame.addMove "Nf6"
    repGame.addMove "Ng1"
    repGame.addMove "Ng8"

    check repGame.repetitionCount() == 2
    check repGame.repetitionCount(-2) == 1

    repGame.addMove "Nf3"
    repGame.addMove "Nf6"
    repGame.addMove "Ng1"
    repGame.addMove "Ng8"

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

  test "fifty move rule detection":
    var fiftyMoveGame = newGame()
    
    # Start with a normal game
    fiftyMoveGame.addMove "e4"
    fiftyMoveGame.addMove "e5"
    fiftyMoveGame.addMove "Nf3"
    fiftyMoveGame.addMove "Nf6"
    
    # At the beginning, 50-move rule should not apply
    check not fiftyMoveGame.fiftyMoveRule()
    check not fiftyMoveGame.fiftyMoveRule(0) # starting position
    
    # Test with invalid indices
    check not fiftyMoveGame.fiftyMoveRule(100) # beyond game length
    check not fiftyMoveGame.fiftyMoveRule(-100) # before game start
    
    # Test with a FEN position that has a high halfmove clock (99 halfmoves)
    # This is just one halfmove away from triggering the 50-move rule
    let highHalfmoveClockFen = "8/8/8/8/8/3k4/3K4/8 w - - 99 50"
    let almostFiftyGame = newGame(fen = highHalfmoveClockFen)
    check not almostFiftyGame.fiftyMoveRule()
    
    # Test with a FEN position that triggers the 50-move rule (100 halfmoves)
    let fiftyMoveRuleFen = "8/8/8/8/8/3k4/3K4/8 w - - 100 51"
    let fiftyRuleTriggeredGame = newGame(fen = fiftyMoveRuleFen)
    check fiftyRuleTriggeredGame.fiftyMoveRule()
    check fiftyRuleTriggeredGame.fiftyMoveRule(0) # check at starting position
    
    # Test with a FEN position that exceeds 50-move rule (120 halfmoves)
    let beyondFiftyMoveFen = "8/8/8/8/8/3k4/3K4/8 b - - 120 61"
    let beyondFiftyGame = newGame(fen = beyondFiftyMoveFen)
    check beyondFiftyGame.fiftyMoveRule()
