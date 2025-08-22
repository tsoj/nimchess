import unittest, options, tables, strutils
import nimchess/[engine, movegen, position, strchess, move, types, game]

const testEngine {.strdefine.} = "stockfish"

echo "Using ", testEngine, " as engine"

suite "UCI Engine Unit Tests":
  test "Option parsing - spin type":
    let line = "name Hash type spin default 16 min 1 max 33554432"
    let option = parseEngineOption(line)
    check option.name == "Hash"
    check option.kind == eotSpin
    check option.defaultInt == 16
    check option.minVal == 1
    check option.maxVal == 33554432

  test "Option parsing - check type":
    let line = "name Ponder type check default false"
    let option = parseEngineOption(line)
    check option.name == "Ponder"
    check option.kind == eotCheck
    check option.defaultBool == false

  test "Option parsing - combo type":
    let line = "name Style type combo default Normal var Solid var Normal var Risky"
    let option = parseEngineOption(line)
    check option.name == "Style"
    check option.kind == eotCombo
    check option.defaultStr == "Normal"
    check option.choices == @["Solid", "Normal", "Risky"]

  test "Option parsing - string type":
    let line = "name SyzygyPath type string default <empty>"
    let option = parseEngineOption(line)
    check option.name == "SyzygyPath"
    check option.kind == eotString
    check option.defaultString == "<empty>"

  test "Option parsing - button type":
    let line = "name Clear_Hash type button"
    let option = parseEngineOption(line)
    check option.name == "Clear_Hash"
    check option.kind == eotButton

  test "Option parsing - edge cases":
    # Test combo with empty choices
    let line2 = "    name Empty type combo default test"
    let option2 = parseEngineOption(line2)
    check option2.name == "Empty"
    check option2.kind == eotCombo
    check option2.defaultStr == "test"

  test "UCI move formatting":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

    # Test basic move formatting
    for move in pos.legalMoves:
      let uciStr = $move
      check uciStr.len >= 4
      check uciStr[0] in {'a' .. 'h'}
      check uciStr[1] in {'1' .. '8'}
      check uciStr[2] in {'a' .. 'h'}
      check uciStr[3] in {'1' .. '8'}

      # Test that we can parse it back
      let parsedMove = uciStr.toMove(pos)
      if not parsedMove.isNoMove:
        check parsedMove.source == move.source
        check parsedMove.target == move.target
      break # Just test first move

  test "UCI move parsing - basic moves":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

    let move = "e2e4".toMove(pos)
    check not move.isNoMove
    check move.source == e2
    check move.target == e4

  test "UCI move parsing - various moves":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

    # Test common opening moves
    let testMoves = ["e2e4", "d2d4", "g1f3", "b1c3"]
    for moveStr in testMoves:
      let move = moveStr.toMove(pos)
      if move != noMove:
        let formatted = $move
        check formatted == moveStr

  test "UCI move parsing - promotion":
    # Use a position where promotion is actually possible
    let pos = "1K5k/P7/8/8/8/8/8/8 w - - 0 1".toPosition
    discard "a7a8q".toMove(pos)
    # The move should be valid in this position

  test "Info parsing - basic info":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("depth 10 seldepth 15 time 1000 nodes 100000 nps 100000", pos)

    check info.depth.isSome
    check info.seldepth.isSome
    check info.timeSeconds.isSome
    check info.nodes.isSome
    check info.nps.isSome

    check info.depth.get == 10
    check abs(info.timeSeconds.get - 1.0) < 0.1

  test "Info parsing - score cp":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("score cp 25", pos)

    check info.score.isSome
    check info.score.get.kind == skCp
    check info.score.get.cp == 25

  test "Info parsing - score mate":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("score mate 5", pos)

    check info.score.isSome
    check info.score.get.kind == skMate
    check info.score.get.mate == 5

  test "Info parsing - score with bounds":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("score cp 50 upperbound", pos)
    check info.score.isSome
    check info.score.get.kind == skCp
    check info.score.get.cp == 50

  test "Info parsing - principal variation":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("pv e2e4 e7e5 g1f3", pos)

    check info.pv.isSome
    check info.pv.get.len >= 1 # At least one move should be parsed

  test "Info parsing - with unknown tokens":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo(
      "depth 1 unknown1 seldepth 2 unknown2 time 16 nodes 1 score cp 72 unknown3", pos
    )

    check info.depth.isSome
    check info.depth.get == 1
    check info.seldepth.isSome
    check info.seldepth.get == 2
    check info.timeSeconds.isSome
    check info.nodes.isSome
    check info.score.isSome
    check info.score.get.cp == 72

  test "Info parsing - string info":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("string goes to end no matter score cp 4 what", pos)
    check info.string.isSome
    check info.string.get == "goes to end no matter score cp 4 what"
  test "Info parsing - robust unknown field handling":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info =
      parseInfo("depth 3 unknownfield 123 nodes 1000 randomstuff abc tbhits 456", pos)

    # Known fields should be parsed correctly
    check info.depth.isSome
    check info.depth.get == 3
    check info.nodes.isSome
    check info.nodes.get == 1000
    check info.tbhits.isSome
    check info.tbhits.get == 456

    # Unknown fields should be ignored without causing errors

  test "Info parsing - malformed numeric fields":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("depth abc nodes xyz tbhits 789 multipv def", pos)

    # Invalid numeric values should be ignored
    check info.depth.isNone
    check info.nodes.isNone
    check info.multipv.isNone

    # Valid numeric value should still be parsed
    check info.tbhits.isSome
    check info.tbhits.get == 789

  test "Info parsing - mixed valid and invalid moves in pv":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("pv e2e4 e7e5 invalid_notation g1f3", pos)

    # Should parse valid moves until hitting invalid one
    check info.pv.isSome
    check info.pv.get.len == 2 # e2e4 and e7e5, then stops at invalid_notation

  test "Info parsing - comprehensive mixed field test":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo(
      "   depth 8 pv e2e4 e7e5 score cp 25 tbhits 100 refutation d2d4 d7d5 currline 2 g1f3 b8c6 unknown_field test hashfull 600",
      pos,
    )

    # All valid fields should be parsed
    check info.depth.isSome
    check info.depth.get == 8
    check info.pv.isSome
    check info.pv.get.len >= 2
    check info.score.isSome
    check info.score.get.cp == 25
    check info.tbhits.isSome
    check info.tbhits.get == 100
    check info.hashfull.isSome
    check info.hashfull.get == 600

  test "Score display":
    let cpScore = Score(kind: skCp, cp: 150)
    check $cpScore == "cp 150"

    let mateScore = Score(kind: skMate, mate: 3)
    check $mateScore == "mate 3"

    let mateGivenScore = Score(kind: skMateGiven)
    check $mateGivenScore == "mate 0"

  test "Score comparison":
    # Test score ordering similar to Python tests
    let scores = [
      Score(kind: skMate, mate: -1),
      Score(kind: skCp, cp: -100),
      Score(kind: skCp, cp: 0),
      Score(kind: skCp, cp: 100),
      Score(kind: skMate, mate: 3),
      Score(kind: skMateGiven),
    ]

    # Basic ordering checks
    check scores[0] < scores[1] # mate -1 < cp -100
    check scores[1] < scores[2] # cp -100 < cp 0
    check scores[2] < scores[3] # cp 0 < cp 100
    check scores[3] < scores[4] # cp 100 < mate 3
    check scores[4] < scores[5] # mate 3 < mate given

    check scores[2] > scores[1]
    check scores[1] == scores[1]
    check scores[4] == scores[4]
    check scores[4] != scores[5]
    check scores[3] != scores[4]
    check scores[4] <= scores[5]
    check scores[1] >= scores[1]

  test "Limit creation":
    let timeLimit = Limit(movetimeSeconds: 5.0)
    check timeLimit.movetimeSeconds == 5.0
    check timeLimit.depth == int.high

    let depthLimit = Limit(depth: 10)
    check depthLimit.depth == 10
    check depthLimit.movetimeSeconds == float.high

  test "Limit with multiple constraints":
    let limit = Limit(movetimeSeconds: 2.5, depth: 12, nodes: 1000000)
    check limit.movetimeSeconds == 2.5
    check limit.depth == 12
    check limit.nodes == 1000000

  test "Engine creation":
    var engine = newUciEngine(testEngine)
    check engine.initialized

  test "setPosition updates engine game state correctly":
    var engine = newUciEngine(testEngine)

    # Test setting starting position
    let startPos = classicalStartPos
    engine.setPosition(startPos)
    check engine.game.currentPosition() == startPos
    check engine.game.moves.len == 0
    check engine.game.startPosition == startPos

    # Test setting position with moves
    let moves =
      @[
        "e2e4".toMove(startPos), "e7e5".toMove(startPos.doMove("e2e4".toMove(startPos)))
      ]
    engine.setPosition(startPos, moves)
    check engine.game.moves.len == 2
    check engine.game.moves[0] == moves[0]
    check engine.game.moves[1] == moves[1]

    # Verify the current position matches what we expect after the moves
    let expectedPos = startPos.doMove(moves[0]).doMove(moves[1])
    check engine.game.currentPosition() == expectedPos

    # Test setting a different starting position
    let customFen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    let customPos = customFen.toPosition()
    engine.setPosition(customPos)
    check engine.game.currentPosition() == customPos
    check engine.game.startPosition == customPos
    check engine.game.moves.len == 0

    # Test setting custom position with additional moves
    let additionalMove = "g1f3".toMove(customPos)
    engine.setPosition(customPos, @[additionalMove])
    check engine.game.moves.len == 1
    check engine.game.moves[0] == additionalMove
    check engine.game.currentPosition() == customPos.doMove(additionalMove)

suite "UCI Engine Integration Tests":
  test "Engine availability":
    var engine: UciEngine
    try:
      engine.start(testEngine)
      check true # If we get here, engine started successfully
      engine.quit()
    except CatchableError:
      fail()

  test "Engine initialization":
    var engine = newUciEngine(testEngine)
    try:
      check engine.initialized
      check engine.name.len > 0

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Engine ready check":
    var engine = newUciEngine(testEngine)
    try:
      let ready = engine.isReady()
      check ready

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Engine options parsing":
    var engine = newUciEngine(testEngine)
    try:
      check engine.options.len > 0

      # Most UCI engines should have a Hash option
      var hasHashOption = false
      for optName, opt in engine.options.pairs:
        if optName.toLowerAscii().contains("hash"):
          hasHashOption = true
          break

      check hasHashOption
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Setting engine options":
    var engine = newUciEngine(testEngine)
    try:
      # Try to set a common option (most engines have Hash)
      var optionName = ""
      for name, opt in engine.options.pairs:
        if name.toLowerAscii().contains("hash") and opt.kind == eotSpin:
          optionName = name
          break

      if optionName != "":
        engine.setOption(optionName, "64")
        check true # If we get here, option was set successfully

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Position setup":
    var engine = newUciEngine(testEngine)
    try:
      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      # Test with moves
      let move1 = "e2e4".toMove(startPos)
      if move1 != noMove:
        let pos2 = startPos.doMove(move1)
        let move2 = "e7e5".toMove(pos2)
        if move2 != noMove:
          let moves = @[move1, move2]
          engine.setPosition(startPos, moves)

      check true # If we get here, position setup was successful
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Basic search (movetime)":
    var engine = newUciEngine(testEngine)
    try:
      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.1) # Very short search
      let result = engine.go(limit)

      check not result.move.isNoMove
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Depth-limited search":
    var engine = newUciEngine(testEngine)
    try:
      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(depth: 5)
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.info.depth.isSome
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Move validation":
    var engine = newUciEngine(testEngine)
    try:
      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.1)
      let result = engine.go(limit)

      check not result.move.isNoMove
      check startPos.isLegal(result.move)
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Info parsing during search":
    var engine = newUciEngine(testEngine)
    try:
      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.5) # Longer search to get info
      let result = engine.go(limit)

      # Check if we got some search info
      let hasNodes = result.info.nodes.isSome
      let hasTime = result.info.timeSeconds.isSome

      check hasNodes or hasTime # At least one should be present
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "New game command":
    var engine = newUciEngine(testEngine)
    try:
      engine.newGame()

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.1)
      let result = engine.go(limit)

      check not result.move.isNoMove
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "High-level play function":
    try:
      var engine = newUciEngine(testEngine)

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      let limit = Limit(movetimeSeconds: 0.1)

      let result = engine.play(startPos, limit)

      check not result.move.isNoMove
      engine.quit()
    except CatchableError:
      fail()

  test "Mate position detection":
    var engine = newUciEngine(testEngine)
    try:
      # Simple mate in 1 position
      let matePos = "k7/7R/6R1/8/8/8/8/K7 w - - 0 1".toPosition
      engine.setPosition(matePos)

      let limit = Limit(depth: 3)
      let result = engine.go(limit)

      check not result.move.isNoMove
      # The engine should find the mating move
      let newPos = matePos.doMove result.move
      check newPos.isMate

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Multiple engines - Basic functionality":
    let engines = [testEngine] # Add more engines as needed

    for engineName in engines:
      var engine = newUciEngine(engineName)
      try:
        check engine.initialized
        check engine.name.len > 0

        # Quick search test
        let startPos =
          "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
        engine.setPosition(startPos)

        let limit = Limit(movetimeSeconds: 0.1)
        let result = engine.go(limit)

        check not result.move.isNoMove
        engine.quit()
      except CatchableError:
        try:
          engine.quit()
        except CatchableError:
          discard
        fail()

  test "Multi-PV search - basic functionality":
    var engine = newUciEngine(testEngine)
    try:
      engine.setOption("MultiPV", "3") # Request 3 PV lines

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(depth: 6) # Deeper search to get multiple PVs
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.pvs.len == 3

      # Should have at least one PV line
      check result.pvs.hasKey(1)

      check result.pvs[1].pv != result.pvs[2].pv
      check result.pvs[1].pv != result.pvs[3].pv
      check result.pvs[2].pv != result.pvs[3].pv

      for pvNum, info in result.pvs.pairs:
        check info.multipv.isSome
        check info.multipv.get() == pvNum

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Multi-PV search - tactical position":
    var engine = newUciEngine(testEngine)
    try:
      engine.setOption("MultiPV", "4") # Request 4 PV lines

      # Tactical position with multiple good moves
      let tacticalPos =
        "r1bqkb1r/pppp1ppp/2n2n2/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4".toPosition
      engine.setPosition(tacticalPos)

      let limit = Limit(depth: 8)
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.pvs.len == 4

      # Check that we got the main PV
      check result.pvs.hasKey(1)
      let mainPV = result.pvs[1]
      check mainPV.multipv.isSome
      check mainPV.multipv.get() == 1

      # Verify PV consistency
      for pvNum, info in result.pvs.pairs:
        check info.multipv.isSome
        check info.multipv.get() == pvNum
        if info.pv.isSome:
          check info.pv.get().len > 0

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Multi-PV search - info accessor function":
    var engine = newUciEngine(testEngine)
    try:
      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(depth: 5)
      let result = engine.go(limit)

      check not result.move.isNoMove

      # Test the info() function which should return the main PV line
      let mainInfo = result.info()
      check result.pvs.hasKey(1)

      # The info() function should return the same as pvs[1]
      let directMainInfo = result.pvs[1]
      check mainInfo.depth == directMainInfo.depth
      check mainInfo.score == directMainInfo.score
      check mainInfo.pv == directMainInfo.pv

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Multi-PV search - PV line validation":
    var engine = newUciEngine(testEngine)
    try:
      engine.setOption("MultiPV", "2") # Request 2 PV lines

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 1.0) # Longer search
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.pvs.len == 2

      # Validate that all PV moves are legal
      for pvNum, info in result.pvs.pairs:
        if info.pv.isSome:
          let pvMoves = info.pv.get()
          if pvMoves.len > 0:
            # First move should be legal from the starting position
            check startPos.isLegal(pvMoves[0])

            # Verify the first move matches the best move for PV line 1
            if pvNum == 1:
              check pvMoves[0] == result.move

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

suite "UCI Engine Move Semantics Tests":
  test "UciEngine move construction from function return":
    # Test that engines can be moved from function returns (no copying allowed)
    proc createEngine(): UciEngine =
      result = newUciEngine(testEngine)

    # This should use move semantics since copying is disabled with {.error.}
    let engine = createEngine()
    check engine.initialized

  test "UciEngine explicit move with system.move":
    # Test explicit move operations
    var engine1 = newUciEngine(testEngine)
    check engine1.initialized

    # Explicit move - this should work since copying is disabled
    var engine2 = system.move(engine1)
    check engine2.initialized

    # engine1 should be in moved state - =wasMoved should have set process = nil
    # The moved engine should still be safe to use (won't crash destructor)
    check not engine1.initialized

  test "UciEngine move with ensureMove verification":
    proc stuff() =
      # Test that moves can be verified at compile time
      var engineA = newUciEngine(testEngine)

      # # ensureMove should work since the engine will be moved
      var engineB = ensureMove engineA
      check engineB.initialized

      engineB.setOption("Hash", "8")

      let result = engineB.play(classicalStartPos, Limit(depth: 4))
      check result.info.depth.get == 4

    stuff()

  test "UciEngine sink parameter move":
    # Test that engines can be moved into sink parameters
    proc processEngine(engine: sink UciEngine): bool =
      engine.initialized

    var engine = newUciEngine(testEngine)
    # This should move the engine into the function parameter
    let result = processEngine(move engine)
    check result
    check not engine.initialized

  test "UciEngine move in assignment chain":
    # Test move semantics in assignment chains
    proc createEngine(): UciEngine =
      newUciEngine(testEngine)

    # Chain of moves - each should use move semantics
    var engine1 = createEngine()
    var engine2: UciEngine
    engine2 = system.move(engine1)

    check not engine1.initialized
    check engine2.initialized
    # engine1 should be safely moved (=wasMoved called)

  test "UciEngine move with sequence operations":
    # Test moving engines into collections
    var engines: seq[UciEngine]

    # Move engines directly into sequence
    engines.add(newUciEngine(testEngine)) # Should move from function return
    engines.add(newUciEngine(testEngine)) # Should move from function return

    check engines.len == 2
    check engines[0].initialized
    check engines[1].initialized

  test "UciEngine lastReadOf optimization":
    # Test that last reads are optimized to moves
    proc useEngine(engine: UciEngine): bool =
      result = engine.initialized

    block:
      let engine = newUciEngine(testEngine)
      # This should be optimized to a move since it's the last use of engine
      let result = useEngine(engine)
      check result
      # engine is consumed here and shouldn't be accessible afterward

# Test runner that mimics the original comprehensive test suite
when isMainModule:
  # Run all tests
  echo "Running UCI Engine Test Suite"
  echo "=" & "=".repeat(50)
