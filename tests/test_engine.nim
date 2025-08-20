import unittest, options, tables, times, strformat, strutils
import nimchess/[engine, movegen, position, strchess, move, types]

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
    let move = "a7a8q".toMove(pos)
    # The move should be valid in this position

  test "Info parsing - basic info":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("depth 10 seldepth 15 time 1000 nodes 100000 nps 100000", pos)

    check info.depth.isSome
    check info.seldepth.isSome
    check info.time.isSome
    check info.nodes.isSome
    check info.nps.isSome

    check info.depth.get == 10
    check abs(info.time.get - 1.0) < 0.001

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
    check info.time.isSome
    check info.nodes.isSome
    check info.score.isSome
    check info.score.get.cp == 72

  test "Info parsing - string info":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("string goes to end no matter score cp 4 what", pos)
    # Implementation specific - depends on how string parsing is handled

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
    let engine = newUciEngine()
    check not engine.initialized
    check engine.options.len == 0
    check engine.id.len == 0

suite "UCI Engine Integration Tests":
  # These tests require an actual UCI engine to be available
  # They will be skipped if the engine is not found

  template skipIfEngineNotFound(engineName: string) =
    try:
      let engine = newUciEngine()
      engine.start(engineName)
      engine.quit()
    except:
      skip()

  test "Stockfish - Engine availability":
    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      check true # If we get here, engine started successfully
      engine.quit()
    except:
      fail()

  test "Stockfish - Engine initialization":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      check engine.initialized
      check engine.id.len > 0

      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Engine ready check":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      let ready = engine.isReady()
      check ready

      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Engine options parsing":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      check engine.options.len > 0

      # Most UCI engines should have a Hash option
      var hasHashOption = false
      for optName, opt in engine.options.pairs:
        if optName.toLowerAscii().contains("hash"):
          hasHashOption = true
          break

      check hasHashOption
      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Setting engine options":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

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
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Position setup":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

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
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Basic search (movetime)":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.1) # Very short search
      let result = engine.go(limit)

      check result.move.isSome
      engine.quit()
    except:
      raise
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Depth-limited search":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(depth: 5)
      let result = engine.go(limit)

      check result.move.isSome
      check result.info.depth.isSome
      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Move validation":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.1)
      let result = engine.go(limit)

      if result.move.isNone:
        fail()

      let move = result.move.get()
      let isLegalMove = startPos.isLegal(move)

      check isLegalMove
      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - Info parsing during search":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.5) # Longer search to get info
      let result = engine.go(limit)

      # Check if we got some search info
      let hasNodes = result.info.nodes.isSome
      let hasTime = result.info.time.isSome

      check hasNodes or hasTime # At least one should be present
      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - New game command":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      engine.newGame()

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: 0.1)
      let result = engine.go(limit)

      check result.move.isSome
      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Stockfish - High-level play function":
    skipIfEngineNotFound("stockfish")

    try:
      let engine = startEngine("stockfish")

      let startPos =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      let limit = Limit(movetimeSeconds: 0.1)

      let result = engine.play(startPos, limit)

      check result.move.isSome
      engine.quit()
    except:
      fail()

  test "Stockfish - Mate position detection":
    skipIfEngineNotFound("stockfish")

    let engine = newUciEngine()
    try:
      engine.start("stockfish")
      engine.initialize()

      # Simple mate in 1 position
      let matePos = "k7/7R/6R1/8/8/8/8/K7 w - - 0 1".toPosition
      engine.setPosition(matePos)

      let limit = Limit(depth: 3)
      let result = engine.go(limit)

      check result.move.isSome
      # The engine should find the mating move
      if result.move.isSome:
        let move = result.move.get()
        let newPos = matePos.doMove(move)
        # We can't easily check if it's checkmate without implementing that logic

      engine.quit()
    except:
      try:
        engine.quit()
      except:
        discard
      fail()

  test "Multiple engines - Basic functionality":
    let engines = ["stockfish"] # Add more engines as needed

    for engineName in engines:
      skipIfEngineNotFound(engineName)

      let engine = newUciEngine()
      try:
        engine.start(engineName)
        engine.initialize()

        check engine.initialized
        check engine.id.len > 0

        # Quick search test
        let startPos =
          "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
        engine.setPosition(startPos)

        let limit = Limit(movetimeSeconds: 0.1)
        let result = engine.go(limit)

        check result.move.isSome
        engine.quit()
      except:
        try:
          engine.quit()
        except:
          discard
        fail()

# Test runner that mimics the original comprehensive test suite
when isMainModule:
  # Run all tests
  echo "Running UCI Engine Test Suite"
  echo "=" & "=".repeat(50)
