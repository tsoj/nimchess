import unittest, options, tables, strutils
import nimchess/[uciclient, position, types, strchess, movegen]
import shared_engine_tests

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
    let line2 = "    name Empty type combo default test"
    let option2 = parseEngineOption(line2)
    check option2.name == "Empty"
    check option2.kind == eotCombo
    check option2.defaultStr == "test"

  test "UCI move formatting":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

    for move in pos.legalMoves:
      let uciStr = $move
      check uciStr.len >= 4
      check uciStr[0] in {'a' .. 'h'}
      check uciStr[1] in {'1' .. '8'}
      check uciStr[2] in {'a' .. 'h'}
      check uciStr[3] in {'1' .. '8'}

      let parsedMove = uciStr.toMove(pos)
      if not parsedMove.isNoMove:
        check parsedMove.source == move.source
        check parsedMove.target == move.target
      break

  test "UCI move parsing - basic moves":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

    let move = "e2e4".toMove(pos)
    check not move.isNoMove
    check move.source == e2
    check move.target == e4

  test "UCI move parsing - various moves":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

    let testMoves = ["e2e4", "d2d4", "g1f3", "b1c3"]
    for moveStr in testMoves:
      let move = moveStr.toMove(pos)
      if move != noMove:
        let formatted = $move
        check formatted == moveStr

  test "UCI move parsing - promotion":
    let pos = "1K5k/P7/8/8/8/8/8/8 w - - 0 1".toPosition
    discard "a7a8q".toMove(pos)

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
    check info.pv.get.len >= 1

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
    check info.depth.isSome
    check info.depth.get == 3
    check info.nodes.isSome
    check info.nodes.get == 1000
    check info.tbhits.isSome
    check info.tbhits.get == 456

  test "Info parsing - malformed numeric fields":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("depth abc nodes xyz tbhits 789 multipv def", pos)
    check info.depth.isNone
    check info.nodes.isNone
    check info.multipv.isNone
    check info.tbhits.isSome
    check info.tbhits.get == 789

  test "Info parsing - mixed valid and invalid moves in pv":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo("pv e2e4 e7e5 invalid_notation g1f3", pos)
    check info.pv.isSome
    check info.pv.get.len == 2

  test "Info parsing - comprehensive mixed field test":
    let pos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
    let info = parseInfo(
      "   depth 8 pv e2e4 e7e5 score cp 25 tbhits 100 refutation d2d4 d7d5 currline 2 g1f3 b8c6 unknown_field test hashfull 600",
      pos,
    )
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
    let scores = [
      Score(kind: skMate, mate: -1),
      Score(kind: skCp, cp: -100),
      Score(kind: skCp, cp: 0),
      Score(kind: skCp, cp: 100),
      Score(kind: skMate, mate: 3),
      Score(kind: skMateGiven),
    ]
    check scores[0] < scores[1]
    check scores[1] < scores[2]
    check scores[2] < scores[3]
    check scores[3] < scores[4]
    check scores[4] < scores[5]
    check scores[2] > scores[1]
    check scores[1] == scores[1]
    check scores[4] == scores[4]
    check scores[4] != scores[5]
    check scores[3] != scores[4]
    check scores[4] <= scores[5]
    check scores[1] >= scores[1]

  test "Limit creation":
    let timeLimit = Limit(movetimeSeconds: some(5.0))
    check timeLimit.movetimeSeconds == some(5.0)
    check timeLimit.depth == int.high
    let depthLimit = Limit(depth: 10)
    check depthLimit.depth == 10
    check depthLimit.movetimeSeconds.isNone

  test "Limit with multiple constraints":
    let limit = Limit(movetimeSeconds: some(2.5), depth: 12, nodes: 1000000)
    check limit.movetimeSeconds == some(2.5)
    check limit.depth == 12
    check limit.nodes == 1000000

# Shared tests that work with any UCI engine
runEngineTests(testEngine = testEngine)

# Stockfish-specific tests
suite "Stockfish-specific Tests":
  test "Engine options parsing":
    var engine = newUciEngine(testEngine)
    try:
      check engine.options.len > 0

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
      var optionName = ""
      for name, opt in engine.options.pairs:
        if name.toLowerAscii().contains("hash") and opt.kind == eotSpin:
          optionName = name
          break

      if optionName != "":
        engine.setOption(optionName, "64")
        check true

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
      let startPos = classicalStartPos
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

  test "Info parsing during search":
    var engine = newUciEngine(testEngine)
    try:
      let startPos = classicalStartPos
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: some 0.5)
      let result = engine.go(limit)

      let hasNodes = result.info.nodes.isSome
      let hasTime = result.info.timeSeconds.isSome

      check hasNodes or hasTime
      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()

  test "Mate position detection":
    var engine = newUciEngine(testEngine)
    try:
      let matePos = "k7/7R/6R1/8/8/8/8/K7 w - - 0 1".toPosition
      engine.setPosition(matePos)

      let limit = Limit(depth: 3)
      let result = engine.go(limit)

      check not result.move.isNoMove
      let newPos = matePos.doMove result.move
      check newPos.isMate

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
      engine.setOption("MultiPV", "3")

      let startPos = classicalStartPos
      engine.setPosition(startPos)

      let limit = Limit(depth: 6)
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.pvs.len == 3
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
      engine.setOption("MultiPV", "4")

      let tacticalPos =
        "r1bqkb1r/pppp1ppp/2n2n2/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4".toPosition
      engine.setPosition(tacticalPos)

      let limit = Limit(depth: 8)
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.pvs.len == 4
      check result.pvs.hasKey(1)
      let mainPV = result.pvs[1]
      check mainPV.multipv.isSome
      check mainPV.multipv.get() == 1

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
      let startPos = classicalStartPos
      engine.setPosition(startPos)

      let limit = Limit(depth: 5)
      let result = engine.go(limit)

      check not result.move.isNoMove

      let mainInfo = result.info()
      check result.pvs.hasKey(1)

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
      engine.setOption("MultiPV", "2")

      let startPos = classicalStartPos
      engine.setPosition(startPos)

      let limit = Limit(movetimeSeconds: some 1.0)
      let result = engine.go(limit)

      check not result.move.isNoMove
      check result.pvs.len == 2

      for pvNum, info in result.pvs.pairs:
        if info.pv.isSome:
          let pvMoves = info.pv.get()
          if pvMoves.len > 0:
            check startPos.isLegal(pvMoves[0])
            if pvNum == 1:
              check pvMoves[0] == result.move

      engine.quit()
    except CatchableError:
      try:
        engine.quit()
      except CatchableError:
        discard
      fail()
