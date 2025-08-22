import std/[osproc, streams, strutils, options, tables]
import position, move, types, strchess, movegen, game

type
  EngineOptionType* = enum
    ## UCI engine option types
    eotCheck = "check"
    eotSpin = "spin"
    eotCombo = "combo"
    eotButton = "button"
    eotString = "string"

  EngineOption* = object ## Represents a UCI engine option
    name*: string
    case kind*: EngineOptionType
    of eotCheck:
      defaultBool*: bool
    of eotSpin:
      defaultInt*: int
      minVal*: int
      maxVal*: int
    of eotCombo:
      defaultStr*: string
      choices*: seq[string]
    of eotButton:
      discard
    of eotString:
      defaultString*: string

  Limit* = object ## Search limit parameters
    movetimeSeconds*: float = float.high ## Search exactly this many seconds
    depth*: int = int.high ## Search to this depth only
    nodes*: int = int.high ## Search only this many nodes
    whiteTimeSeconds*: float = float.high ## Time remaining for white (seconds)
    blackTimeSeconds*: float = float.high ## Time remaining for black (seconds)
    whiteIncSeconds*: float = 0.0 ## White increment per move (seconds)
    blackIncSeconds*: float = 0.0 ## Black increment per move (seconds)
    movesToGo*: int = int.high ## Moves until next time control

  ScoreKind* = enum
    skCp ## Centipawn score
    skMate ## Mate in N moves
    skMateGiven ## Mate is given (mate in 0)

  Score* = object ## Represents an evaluation score
    case kind*: ScoreKind
    of skCp:
      cp*: int
    of skMate:
      mate*: int ## Positive = we mate, negative = we get mated
    of skMateGiven:
      discard

  UciInfo* = object ## Information from UCI engine during search
    depth*: Option[int] ## Search depth in plies
    seldepth*: Option[int] ## Selective search depth
    time*: Option[float] ## Time searched in seconds
    nodes*: Option[int] ## Nodes searched
    nps*: Option[int] ## Nodes per second
    score*: Option[Score] ## Current evaluation
    pv*: Option[seq[Move]] ## Principal variation (empty if none)
    multipv*: Option[int] ## Multi-PV line number
    string*: Option[string] ## Arbitrary string from engine
    currmove*: Option[Move] ## Currently searching move
    currmovenumber*: Option[int] ## Move number being searched
    hashfull*: Option[int] ## Hash table fill level (permille)
    tbhits*: Option[int] ## Tablebase hits
    sbhits*: Option[int] ## Shredder endgame database hits
    cpuload*: Option[int] ## CPU usage in permille
    refutation*: Option[seq[Move]] ## Refutation line for a move
    currline*: Option[(int, seq[Move])]
      ## Current line being calculated (CPU number, moves)

  PlayResult* = object ## Result from asking engine to play a move
    move*: Option[Move] ## Best move found
    ponder*: Option[Move] ## Expected opponent response
    info*: UciInfo ## Additional search information
    drawOffered*: bool ## Whether engine offered a draw
    resigned*: bool ## Whether engine resigned

  UciEngine* = object ## UCI chess engine communication handler
    process: Process = nil
    options*: Table[string, EngineOption]
    id*: Table[string, string]
    debug: bool = false
    game*: Game = default Game

func initialized*(engine: UciEngine): bool =
  engine.process != nil

proc `=copy`*(dest: var UciEngine, source: UciEngine) {.error.}

proc `=wasMoved`*(engine: var UciEngine) {.nodestroy.} =
  ## Mark engine as moved - reset to safe state
  engine.process = nil

proc `=destroy`*(engine: var UciEngine) =
  ## Destructor for UciEngine - ensures process is properly closed
  if engine.initialized:
    try:
      engine.process.inputStream.writeLine("quit")
      engine.process.inputStream.flush()
    except CatchableError:
      discard # Ignore errors during cleanup
    try:
      engine.process.close()
    except IOError, OSError:
      discard # Ignore errors during process cleanup

proc `<`*(a, b: Score): bool =
  if a.kind == skMateGiven:
    return false
  if b.kind == skMateGiven:
    return true
  if a.kind == skMate and b.kind == skMate:
    if a.mate > 0 and b.mate > 0:
      return a.mate > b.mate
    if a.mate < 0 and b.mate < 0:
      return a.mate < b.mate
    return a.mate < b.mate
  if a.kind == skMate and b.kind == skCp:
    return a.mate < 0
  if a.kind == skCp and b.kind == skMate:
    return b.mate > 0
  return a.cp < b.cp # both skCp

proc `$`*(score: Score): string =
  case score.kind
  of skCp:
    "cp " & $score.cp
  of skMate:
    "mate " & $score.mate
  of skMateGiven:
    "mate 0"

# Engine communication

proc sendCommand(engine: var UciEngine, command: string) =
  ## Send a command to the engine
  if not engine.initialized:
    raise newException(ValueError, "Engine not initialized")
  assert engine.process.inputStream != nil

  if engine.debug:
    echo ">> ", command

  engine.process.inputStream.writeLine(command)
  engine.process.inputStream.flush()

proc readLine(engine: var UciEngine): string =
  ## Read a line from the engine
  if not engine.initialized:
    raise newException(ValueError, "Engine not initialized")
  assert engine.process.inputStream != nil

  result = engine.process.outputStream.readLine()

  if engine.debug:
    echo "<< ", result

  result = result.strip()

proc parseEngineOption*(line: string): EngineOption =
  ## Parse a UCI option line
  # Format: option name <name> type <type> [default <value>] [min <value>] [max <value>] [var <choice>]*
  var
    properties: Table[string, string]
    choices: seq[string] = @[]

  let parts = line.splitWhitespace()

  for i in countup(1, parts.len - 1, 2):
    let
      key = parts[i - 1]
      value = parts[i]
    if key == "var":
      choices.add value
    else:
      properties[key] = value

  let
    name = properties.getOrDefault("name", "No option name given")
    optionType = properties.getOrDefault("type", "No type given")
  # Create the option based on type
  case optionType
  of "check":
    result = EngineOption(
      name: name,
      kind: eotCheck,
      defaultBool: properties.getOrDefault("default", "true").parseBool,
    )
  of "spin":
    let
      defaultInt = properties.getOrDefault("default", "0").parseInt
      minInt = properties.getOrDefault("min", $int.low).parseInt
      maxInt = properties.getOrDefault("max", $int.high).parseInt
    result = EngineOption(
      name: name, kind: eotSpin, defaultInt: defaultInt, minVal: minInt, maxVal: maxInt
    )
  of "combo":
    result = EngineOption(
      name: name,
      kind: eotCombo,
      defaultStr: properties.getOrDefault("default"),
      choices: choices,
    )
  of "button":
    result = EngineOption(name: name, kind: eotButton)
  of "string":
    result = EngineOption(
      name: name, kind: eotString, defaultString: properties.getOrDefault("default")
    )
  else:
    raise newException(ValueError, "Unknown option type: " & optionType)

proc parseInfo*(line: string, position: Position): UciInfo =
  ## Parse a UCI info line
  let parts = line.splitWhitespace()
  var i = 0

  proc parseIntField(field: var Option[int]) =
    i += 1
    if i < parts.len:
      try:
        field = some(parseInt(parts[i]))
      except ValueError:
        discard

  proc parseFloatField(field: var Option[float], divisor: float = 1.0) =
    i += 1
    if i < parts.len:
      try:
        field = some(parseInt(parts[i]).float / divisor)
      except ValueError:
        discard

  proc parseMoveSequence(moves: var Option[seq[Move]], pos: Position) =
    i += 1
    moves = some newSeq[Move]()
    var tempPos = pos
    while i < parts.len:
      try:
        let move = parts[i].toMove(tempPos)
        moves.get.add(move)
        tempPos = tempPos.doMove(move)
        i += 1
      except ValueError:
        break

  proc parseMoveSequenceFromCurrent(moves: var Option[seq[Move]], pos: Position) =
    moves = some newSeq[Move]()
    var tempPos = pos
    while i < parts.len:
      try:
        let move = parts[i].toMove(tempPos)
        moves.get.add(move)
        tempPos = tempPos.doMove(move)
        i += 1
      except ValueError:
        break

  proc parseMove(moveField: var Option[Move], pos: Position) =
    i += 1
    if i < parts.len:
      try:
        moveField = some(parts[i].toMove(pos))
      except ValueError:
        discard

  while i < parts.len:
    case parts[i]
    of "depth":
      parseIntField(result.depth)
    of "seldepth":
      parseIntField(result.seldepth)
    of "time":
      parseFloatField(result.time, 1000.0)
    of "nodes":
      parseIntField(result.nodes)
    of "nps":
      parseIntField(result.nps)
    of "score":
      i += 1
      if i + 1 < parts.len:
        case parts[i]
        of "cp":
          i += 1
          try:
            result.score = some(Score(kind: skCp, cp: parseInt(parts[i])))
          except ValueError:
            discard
        of "mate":
          i += 1
          try:
            let mateVal = parseInt(parts[i])
            if mateVal == 0:
              result.score = some(Score(kind: skMateGiven))
            else:
              result.score = some(Score(kind: skMate, mate: mateVal))
          except ValueError:
            discard
    of "pv":
      parseMoveSequence(result.pv, position)
      continue
    of "multipv":
      parseIntField(result.multipv)
    of "currmove":
      parseMove(result.currmove, position)
    of "currmovenumber":
      parseIntField(result.currmovenumber)
    of "hashfull":
      parseIntField(result.hashfull)
    of "tbhits":
      parseIntField(result.tbhits)
    of "sbhits":
      parseIntField(result.sbhits)
    of "cpuload":
      parseIntField(result.cpuload)
    of "refutation":
      parseMoveSequence(result.refutation, position)
      continue
    of "currline":
      i += 1
      if i < parts.len:
        try:
          let cpuNum = parseInt(parts[i])
          i += 1
          var moves: Option[seq[Move]]
          parseMoveSequenceFromCurrent(moves, position)
          if moves.isSome:
            result.currline = some((cpuNum, moves.get))
        except ValueError:
          discard
      continue
    of "string":
      i += 1
      if i < parts.len:
        result.string = some(parts[i ..^ 1].join(" "))
      break
    i += 1

proc initialize(engine: var UciEngine) =
  engine.sendCommand("uci")

  while true:
    let line = engine.readLine()
    if line.len == 0:
      continue

    let parts = line.split(maxsplit = 1)
    if parts.len == 0:
      continue

    case parts[0]
    of "id":
      if parts.len > 1:
        let idParts = parts[1].split(maxsplit = 1)
        if idParts.len == 2:
          engine.id[idParts[0]] = idParts[1]
    of "option":
      if parts.len > 1:
        try:
          let option = parseEngineOption(parts[1])
          engine.options[option.name] = option
        except:
          discard # Ignore malformed options
    of "uciok":
      return
    else:
      discard

proc start*(engine: var UciEngine, command: string, args: openArray[string] = []) =
  ## Start the engine process

  if engine.initialized:
    raise newException(ValueError, "Engine already initialized")

  var allArgs = @[command]
  allArgs.add(args)

  engine.process = startProcess(
    command = command, args = args, options = {poUsePath, poStdErrToStdOut}
  )

  engine.initialize

proc newUciEngine*(command: string, args: openArray[string] = []): UciEngine =
  ## Convenience function to start and initialize an engine
  # result = default UciEngine
  result.start(command, args)

proc stop*(engine: var UciEngine) =
  ## Stop current search
  engine.sendCommand("stop")

proc quit*(engine: var UciEngine) =
  if engine.initialized:
    engine.sendCommand("quit")
    engine.process.close()

  # Mark as moved to prevent destructor from running cleanup again
  wasMoved(engine)

proc close*(engine: var UciEngine) =
  ## Close the engine process
  engine.quit()

proc setOption*(
    engine: var UciEngine, name: string, value: string, suppressWarning = false
) =
  ## Set an engine option

  if not suppressWarning and name notin engine.options:
    echo "WARNING: Option not listed by engine: ", name

  let cmd = "setoption name " & name & " value " & value
  engine.sendCommand(cmd)

proc isReady*(engine: var UciEngine): bool =
  ## Check if engine is ready
  engine.sendCommand("isready")

  let line = engine.readLine()
  return line == "readyok"

proc newGame*(engine: var UciEngine) =
  engine.sendCommand("ucinewgame")

proc setPosition*(engine: var UciEngine, position: Position, moves: seq[Move] = @[]) =
  ## Set the current position
  # Create a new game with the given starting position
  engine.game = newGame(startPosition = position)

  # Add all the moves to the game
  for move in moves:
    engine.game.addMove(move)

  # Check if this is the starting position
  var cmd = ""

  if position.fen() == classicalStartPos.fen():
    cmd = "position startpos"
  else:
    cmd = "position fen " & position.fen()

  if moves.len > 0:
    cmd.add(" moves")
    for move in moves:
      cmd.add(" " & $move)

  engine.sendCommand(cmd)

proc go*(engine: var UciEngine, limit: Limit): PlayResult =
  ## Ask engine to search and return best move
  var cmd = "go"

  if limit.movetimeSeconds < limit.movetimeSeconds.typeof.high:
    cmd.add(" movetime " & $(int(limit.movetimeSeconds * 1000)))

  if limit.depth < limit.depth.typeof.high:
    cmd.add(" depth " & $limit.depth)
  if limit.nodes < limit.nodes.typeof.high:
    cmd.add(" nodes " & $limit.nodes)

  if limit.whiteTimeSeconds < limit.whiteTimeSeconds.typeof.high:
    cmd.add(" wtime " & $(int(limit.whiteTimeSeconds * 1000)))
  if limit.blackTimeSeconds < limit.blackTimeSeconds.typeof.high:
    cmd.add(" btime " & $(int(limit.blackTimeSeconds * 1000)))

  if limit.whiteIncSeconds != 0.0:
    cmd.add(" winc " & $(int(limit.whiteIncSeconds * 1000)))
  if limit.blackIncSeconds != 0.0:
    cmd.add(" binc " & $(int(limit.blackIncSeconds * 1000)))

  if limit.movesToGo >= 0:
    cmd.add(" movestogo " & $limit.movesToGo)

  engine.sendCommand(cmd)

  while true:
    let line = engine.readLine()
    if line.len == 0:
      continue

    let parts = line.splitWhitespace(maxsplit = 1)
    if parts.len == 0:
      continue

    case parts[0]
    of "info":
      if parts.len > 1:
        let info = parseInfo(parts[1], engine.game.currentPosition())
        for infoOpt, resultOpt in fields(info, result.info):
          if infoOpt.isSome:
            resultOpt = infoOpt
    of "bestmove":
      if parts.len > 1:
        let moveParts = parts[1].split()
        if moveParts.len > 0:
          try:
            let move = moveParts[0].toMove(engine.game.currentPosition())
            result.move = some(move)

            # Check for ponder move
            if moveParts.len > 2 and moveParts[1] == "ponder":
              try:
                let ponderMove =
                  moveParts[2].toMove(engine.game.currentPosition().doMove(move))
                result.ponder = some(ponderMove)
              except ValueError:
                discard
          except ValueError:
            discard

      break
    else:
      discard

# High-level convenience functions

proc play*(
    engine: var UciEngine, position: Position, limit: Limit, moves: seq[Move] = @[]
): PlayResult =
  discard engine.isReady()
  engine.setPosition(position, moves)
  result = engine.go(limit)
