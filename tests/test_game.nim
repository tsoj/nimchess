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

  test "repetition detection - threefold (claimable) vs fivefold (automatic draw)":
    var repGame = newGame()

    check repGame.repetitionCount() == 1

    # First repetition cycle
    repGame.addMove "Nf3"
    repGame.addMove "Nf6"
    repGame.addMove "Ng1"
    repGame.addMove "Ng8"

    check repGame.repetitionCount() == 2
    check repGame.repetitionCount(-2) == 1

    # Second repetition cycle
    repGame.addMove "Nf3"
    repGame.addMove "Nf6"
    repGame.addMove "Ng1"
    repGame.addMove "Ng8"

    # Test repetition counting at different positions
    for i in 0 .. 8:
      check repGame.repetitionCount(i) == 1 + i div 4

    try:
      discard repGame.repetitionCount(9)
      check false
    except IndexDefect:
      discard

    # After third occurrence (threefold repetition)
    check repGame.hasRepetition()
    check not repGame.fivefoldRepetition()
    check repGame.result == "*" # Threefold is claimable, not automatic

    # Third repetition cycle
    repGame.addMove "Nf3"
    repGame.addMove "Nf6"
    repGame.addMove "Ng1"
    repGame.addMove "Ng8"
    check repGame.result == "*" # Still ongoing

    # Fourth repetition cycle
    repGame.addMove "Nf3"
    repGame.addMove "Nf6"
    repGame.addMove "Ng1"
    repGame.addMove "Ng8"

    # After fifth occurrence (fivefold repetition) - should automatically draw
    check repGame.repetitionCount() == 5
    check repGame.hasRepetition()
    check repGame.fivefoldRepetition()
    check repGame.result == "1/2-1/2" # Fivefold is mandatory, automatic

    # Test fivefold repetition at different positions
    check repGame.fivefoldRepetition(-1) # current position
    check not repGame.fivefoldRepetition(0) # starting position
    check not repGame.fivefoldRepetition(4) # after first repetition cycle

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

  test "move rule detection - fifty move (claimable) vs seventy-five move (automatic draw)":
    var normalGame = newGame()

    # Start with a normal game
    normalGame.addMove "e4"
    normalGame.addMove "e5"
    normalGame.addMove "Nf3"
    normalGame.addMove "Nf6"

    # At the beginning, neither rule should apply
    check not normalGame.fiftyMoveRule()
    check not normalGame.seventyFiveMoveRule()
    check not normalGame.fiftyMoveRule(0) # starting position
    check not normalGame.seventyFiveMoveRule(0) # starting position

    # Test with a FEN position that has a high halfmove clock (99 halfmoves)
    # This is just one halfmove away from triggering the 50-move rule
    let highHalfmoveClockFen = "8/8/8/8/8/2k5/8/K6R w - - 99 50"
    let almostFiftyGame = newGame(fen = highHalfmoveClockFen)
    check not almostFiftyGame.fiftyMoveRule()
    check not almostFiftyGame.seventyFiveMoveRule()

    # Test with a FEN position that triggers the 50-move rule (100 halfmoves)
    let fiftyMoveRuleFen = "8/8/8/8/8/2k5/8/K6R w - - 100 51"
    let fiftyRuleTriggeredGame = newGame(fen = fiftyMoveRuleFen)
    check fiftyRuleTriggeredGame.fiftyMoveRule()
    check not fiftyRuleTriggeredGame.seventyFiveMoveRule()
    check fiftyRuleTriggeredGame.result == "*" # 50-move rule is claimable, not automatic

    # Test with a FEN position that has a high halfmove clock (149 halfmoves)
    # This is just one halfmove away from triggering the 75-move rule
    let highSeventyFiveHalfmoveClockFen = "8/8/8/8/8/2k5/8/K6R w - - 149 75"
    let almostSeventyFiveGame = newGame(fen = highSeventyFiveHalfmoveClockFen)
    check almostSeventyFiveGame.fiftyMoveRule() # Should trigger 50-move rule
    check not almostSeventyFiveGame.seventyFiveMoveRule()
    check almostSeventyFiveGame.result == "*" # Still not automatic

    # Test with a FEN position that triggers the 75-move rule (150 halfmoves)
    let seventyFiveMoveRuleFen = "8/8/8/8/8/2k5/8/K6R w - - 150 76"
    let seventyFiveRuleTriggeredGame = newGame(fen = seventyFiveMoveRuleFen)
    check seventyFiveRuleTriggeredGame.fiftyMoveRule() # Should also trigger 50-move rule
    check seventyFiveRuleTriggeredGame.seventyFiveMoveRule()
    check seventyFiveRuleTriggeredGame.result == "1/2-1/2"
      # 75-move rule is mandatory, automatic

    # Test with a FEN position that exceeds both rules (200 halfmoves)
    let beyondBothRulesFen = "8/8/8/8/8/2k5/8/K6R b - - 200 101"
    let beyondBothGame = newGame(fen = beyondBothRulesFen)
    check beyondBothGame.fiftyMoveRule()
    check beyondBothGame.seventyFiveMoveRule()
    check beyondBothGame.result == "1/2-1/2" # Should automatically be a draw

  test "insufficient material":
    # King vs king
    check newGame(fen = "8/8/8/4k3/8/8/8/K7 w - - 0 1").insufficientMaterial()
    # King and minor piece vs king
    check newGame(fen = "8/8/8/4k3/8/8/8/KB6 w - - 0 1").insufficientMaterial()
    check newGame(fen = "8/8/8/4k3/8/8/8/KN6 w - - 0 1").insufficientMaterial()
    # Bishops all on the same square color (b1 and e4 are both light squares)
    check newGame(fen = "8/8/8/4k3/4b3/8/8/KB6 w - - 0 1").insufficientMaterial()
    # Bishops on different square colors
    check not newGame(fen = "8/8/8/4k3/3b4/8/8/KB6 w - - 0 1").insufficientMaterial()
    # Two knights
    check not newGame(fen = "8/8/8/4k3/8/8/8/KNN5 w - - 0 1").insufficientMaterial()
    # Any pawn, rook or queen is sufficient
    check not newGame(fen = "8/8/8/4k3/8/8/P7/K7 w - - 0 1").insufficientMaterial()
    check not newGame(fen = "8/8/8/4k3/8/8/8/KR6 w - - 0 1").insufficientMaterial()
    check not newGame(fen = "8/8/8/4k3/8/8/8/KQ6 w - - 0 1").insufficientMaterial()

    # Insufficient material is a mandatory draw
    check newGame(fen = "8/8/8/4k3/8/8/8/KB6 w - - 0 1").result == "1/2-1/2"

    # Capturing the last piece leads to a dead position and ends the game
    var game1 = newGame(fen = "k7/8/8/8/8/8/q7/K7 w - - 0 1")
    check not game1.insufficientMaterial()
    game1.addMove "Kxa2"
    check game1.insufficientMaterial()
    check not game1.insufficientMaterial(0)
    check game1.result == "1/2-1/2"

  test "isGameOver":
    check not newGame().isGameOver()

    # Checkmate and stalemate
    check newGame(fen = "k1K5/8/8/8/8/8/8/Q7 b - - 0 1").isGameOver() # mate
    check newGame(fen = "k7/8/1Q6/8/8/8/8/7K b - - 0 1").isGameOver() # stalemate

    # Insufficient material
    check newGame(fen = "8/8/8/4k3/8/8/8/KB6 w - - 0 1").isGameOver()

    # 50-move rule and threefold repetition only end the game if claimed
    let fiftyGame = newGame(fen = "8/8/8/8/8/2k5/8/K6R w - - 100 51")
    check not fiftyGame.isGameOver()
    check fiftyGame.isGameOver(claimFiftyMoveRule = true)

    var repGame = newGame()
    for _ in 1 .. 2:
      repGame.addMove "Nf3"
      repGame.addMove "Nf6"
      repGame.addMove "Ng1"
      repGame.addMove "Ng8"
    check not repGame.isGameOver()
    check repGame.isGameOver(claimThreefoldRepetition = true)

    # Mandatory endings need no claim
    check newGame(fen = "8/8/8/8/8/2k5/8/K6R w - - 150 76").isGameOver()
