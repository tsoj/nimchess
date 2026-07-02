import std/options
import unittest
import nimchess/[uciclient, strchess, game]

proc runEngineTests*(testEngine: string) =
  suite "UCI Engine Integration Tests (" & testEngine & ")":
    test "Engine availability":
      var engine: UciEngineProcess
      try:
        engine.start(testEngine)
        check true
        engine.quit()
      except CatchableError:
        fail()

    test "Engine initialization":
      var engine = newUciEngineProcess(testEngine)
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
      var engine = newUciEngineProcess(testEngine)
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

    test "Position setup":
      var engine = newUciEngineProcess(testEngine)
      try:
        let startPos =
          "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
        engine.setPosition(startPos)

        let move1 = "e2e4".toMove(startPos)
        let pos2 = startPos.doMove(move1)
        let move2 = "e7e5".toMove(pos2)
        engine.setPosition(startPos, @[move1, move2])

        check true
        engine.quit()
      except CatchableError:
        try:
          engine.quit()
        except CatchableError:
          discard
        fail()

    test "setPosition updates engine game state correctly":
      var engine = newUciEngineProcess(testEngine)

      let startPos = classicalStartPos
      engine.setPosition(startPos)
      check engine.game.currentPosition() == startPos
      check engine.game.moves.len == 0
      check engine.game.startPosition == startPos

      let moves = @[
        "e2e4".toMove(startPos), "e7e5".toMove(startPos.doMove("e2e4".toMove(startPos)))
      ]
      engine.setPosition(startPos, moves)
      check engine.game.moves.len == 2
      check engine.game.moves[0] == moves[0]
      check engine.game.moves[1] == moves[1]

      let expectedPos = startPos.doMove(moves[0]).doMove(moves[1])
      check engine.game.currentPosition() == expectedPos

      let customFen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
      let customPos = customFen.toPosition()
      engine.setPosition(customPos)
      check engine.game.currentPosition() == customPos
      check engine.game.startPosition == customPos
      check engine.game.moves.len == 0

      let additionalMove = "g1f3".toMove(customPos)
      engine.setPosition(customPos, @[additionalMove])
      check engine.game.moves.len == 1
      check engine.game.moves[0] == additionalMove
      check engine.game.currentPosition() == customPos.doMove(additionalMove)

    test "Basic search (movetime)":
      var engine = newUciEngineProcess(testEngine)
      try:
        let startPos = classicalStartPos
        engine.setPosition(startPos)

        let limit = Limit(movetimeSeconds: some(0.1))
        let result = engine.go(limit)

        check not result.move.isNoMove
        engine.quit()
      except CatchableError:
        try:
          engine.quit()
        except CatchableError:
          discard
        fail()

    test "Move validation":
      var engine = newUciEngineProcess(testEngine)
      try:
        let startPos = classicalStartPos
        engine.setPosition(startPos)

        let limit = Limit(movetimeSeconds: some(0.1))
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

    test "New game command":
      var engine = newUciEngineProcess(testEngine)
      try:
        engine.newGame()

        let startPos = classicalStartPos
        engine.setPosition(startPos)

        let limit = Limit(movetimeSeconds: some(0.1))
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
        var engine = newUciEngineProcess(testEngine)

        let startPos = classicalStartPos
        let limit = Limit(movetimeSeconds: some(0.1))

        let result = engine.play(startPos, limit)

        check not result.move.isNoMove
        engine.quit()
      except CatchableError:
        fail()

    test "Multiple positions search":
      var engine = newUciEngineProcess(testEngine)
      try:
        for fen in [
          "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
          "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
          "r1bqkb1r/pppp1ppp/2n2n2/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
        ]:
          let pos = fen.toPosition
          engine.setPosition(pos)
          let result = engine.go(Limit(movetimeSeconds: some(0.1)))
          check not result.move.isNoMove
          check pos.isLegal(result.move)

        engine.quit()
      except CatchableError:
        try:
          engine.quit()
        except CatchableError:
          discard
        fail()

  suite "UCI Engine Move Semantics Tests (" & testEngine & ")":
    test "UciEngineProcess move construction from function return":
      proc createEngine(): UciEngineProcess =
        result = newUciEngineProcess(testEngine)

      let engine = createEngine()
      check engine.initialized

    test "UciEngineProcess explicit move with system.move":
      var engine1 = newUciEngineProcess(testEngine)
      check engine1.initialized

      var engine2 = system.move(engine1)
      check engine2.initialized
      check not engine1.initialized

    test "UciEngineProcess move with ensureMove verification":
      proc stuff() =
        var engineA = newUciEngineProcess(testEngine)
        var engineB = ensureMove engineA
        check engineB.initialized

        let result = engineB.play(classicalStartPos, Limit(movetimeSeconds: some(0.1)))
        check not result.move.isNoMove

      stuff()

    test "UciEngineProcess sink parameter move":
      proc processEngine(engine: sink UciEngineProcess): bool =
        engine.initialized

      var engine = newUciEngineProcess(testEngine)
      let result = processEngine(move engine)
      check result
      check not engine.initialized

    test "UciEngineProcess move in assignment chain":
      proc createEngine(): UciEngineProcess =
        newUciEngineProcess(testEngine)

      var engine1 = createEngine()
      var engine2: UciEngineProcess
      engine2 = system.move(engine1)

      check not engine1.initialized
      check engine2.initialized

    test "UciEngineProcess move with sequence operations":
      var engines: seq[UciEngineProcess]
      engines.add(newUciEngineProcess(testEngine))
      engines.add(newUciEngineProcess(testEngine))

      check engines.len == 2
      check engines[0].initialized
      check engines[1].initialized

    test "UciEngineProcess lastReadOf optimization":
      proc useEngine(engine: UciEngineProcess): bool =
        result = engine.initialized

      block:
        let engine = newUciEngineProcess(testEngine)
        let result = useEngine(engine)
        check result
