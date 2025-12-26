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
    timeSeconds*: Option[float] ## Time searched in seconds
    nodes*: Option[int] ## Nodes searched
    nps*: Option[int] ## Nodes per second
    score*: Option[Score] ## Current evaluation
    pv*: Option[seq[Move]] ## Principal variation (empty if none)
    multipv*: Option[int] ## Multi-PV line number
    string*: Option[string] ## Arbitrary string from engine
    hashfull*: Option[int] ## Hash table fill level (permille)
    tbhits*: Option[int] ## Tablebase hits

  PlayResult* = object ## Result from asking engine to play a move
    move*: Move = noMove ## Best move found
    ponder*: Option[Move] ## Expected opponent response
    pvs*: Table[int, UciInfo] ## All principal variations (multipv) and search info

  UciEngine* = object ## UCI chess engine communication handler
    process: Process = nil
    options*: Table[string, EngineOption]
    name*: string
    author*: string
    game*: Game = default Game
    debug: bool = false

func initialized*(engine: UciEngine): bool =
  engine.process != nil

proc debugPrint(engine: UciEngine, s: string) =
  if engine.debug:
    echo engine.name, " ", engine.process.processID, " ", s

proc sendCommand(engine: var UciEngine, command: string) =
  ## Send a command to the engine
  if not engine.initialized:
    raise newException(ValueError, "Engine not initialized")
  assert engine.process.inputStream != nil

  engine.debugPrint "<< " & command

  engine.process.inputStream.writeLine(command)
  engine.process.inputStream.flush()

proc readLine(engine: var UciEngine): string =
  ## Read a line from the engine
  if not engine.initialized:
    raise newException(ValueError, "Engine not initialized")
  assert engine.process.inputStream != nil

  result = engine.process.outputStream.readLine()

  engine.debugPrint ">> " & result

  result = result.strip()

func `=copy`*(dest: var UciEngine, source: UciEngine) {.error.}

func `=wasMoved`*(engine: var UciEngine) =
  ## Mark engine as moved - reset to safe state
  `=wasMoved`(engine.process)

proc `=destroy`*(engine: var UciEngine) =
  ## Destructor for UciEngine - ensures process is properly closed
  if engine.initialized:
    try:
      engine.sendCommand("quit")
    except CatchableError:
      discard # Ignore errors during cleanup
    try:
      engine.process.close()
    except IOError, OSError:
      discard # Ignore errors during process cleanup

func `==`*(a, b: Score): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of skCp:
    return a.cp == b.cp
  of skMate:
    return a.mate == b.mate
  of skMateGiven:
    return true

func `<`*(a, b: Score): bool =
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

func `<=`*(a, b: Score): bool =
  a < b or a == b

func `$`*(score: Score): string =
  case score.kind
  of skCp:
    "cp " & $score.cp
  of skMate:
    "mate " & $score.mate
  of skMateGiven:
    "mate 0"

func info*(playResult: PlayResult): UciInfo =
  ## Gets the UCI info of the main PV line.
  ## An alias for `playResult.pvs.getOrDefault(1)`, i.e. accessing the first multipv line.
  playResult.pvs.getOrDefault(1)

func parseEngineOption*(line: string): EngineOption =
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

func parseInfo*(line: string, position: Position): UciInfo =
  ## Parse a UCI info line and returns a new UciInfo object.
  let parts = line.splitWhitespace()
  var i = 0

  func parseIntField(field: var Option[int]) =
    i += 1
    if i < parts.len:
      try:
        field = some(parseInt(parts[i]))
      except ValueError:
        discard

  while i < parts.len:
    case parts[i]
    of "depth":
      parseIntField(result.depth)
    of "seldepth":
      parseIntField(result.seldepth)
    of "nodes":
      parseIntField(result.nodes)
    of "nps":
      parseIntField(result.nps)
    of "multipv":
      parseIntField(result.multipv)
    of "hashfull":
      parseIntField(result.hashfull)
    of "tbhits":
      parseIntField(result.tbhits)
    of "time":
      i += 1
      if i < parts.len:
        try:
          result.timeSeconds = some(parseInt(parts[i]).float / 1000.0)
        except ValueError:
          discard
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
      i += 1
      result.pv = some newSeq[Move]()
      var tempPos = position
      while i < parts.len:
        try:
          let move = parts[i].toMove(tempPos)
          result.pv.get.add(move)
          tempPos = tempPos.doMove(move)
          i += 1
        except ValueError:
          break
      continue
    of "string":
      i += 1
      if i < parts.len:
        result.string = some(parts[i ..^ 1].join(" "))
      break # String is always the last part of an info line
    else:
      discard # Ignore unknown info tokens
    i += 1

proc setPosition*(engine: var UciEngine, game: Game) =
  ## Set the current position of the engine state

  engine.game = game

  # Check if this is the starting position
  var cmd = ""

  if engine.game.startPosition.fen() == classicalStartPos.fen():
    cmd = "position startpos"
  else:
    cmd = "position fen " & engine.game.startPosition.fen()

  if game.moves.len > 0:
    cmd.add(" moves ")
    cmd.add game.moves.notation(engine.game.startPosition)

  engine.sendCommand(cmd)

proc setPosition*(engine: var UciEngine, position: Position, moves: seq[Move] = @[]) =
  # Create a new game with the given starting position
  var game = newGame(startPosition = position)

  # Add all the moves to the game
  for move in moves:
    game.addMove(move)

  engine.setPosition(game)

proc uciInitialize(engine: var UciEngine) =
  engine.sendCommand("uci")

  while true:
    let line = engine.readLine()
    if line.len == 0:
      continue

    let parts = line.splitWhitespace(maxsplit = 1)
    if parts.len == 0:
      continue

    case parts[0]
    of "id":
      if parts.len > 1:
        let idParts = parts[1].splitWhitespace(maxsplit = 1)
        case idParts[0]
        of "name":
          engine.name = idParts[1]
        of "author":
          engine.author = idParts[1]
        else:
          discard
    of "option":
      if parts.len > 1:
        try:
          let option = parseEngineOption(parts[1])
          engine.options[option.name] = option
        except:
          discard
    of "uciok":
      break
    else:
      discard

  engine.setPosition(engine.game)

proc start*(engine: var UciEngine, command: string, args: openArray[string] = []) =
  ## Start the engine process

  if engine.initialized:
    raise newException(ValueError, "Engine already initialized")

  var allArgs = @[command]
  allArgs.add(args)

  engine.process = startProcess(
    command = command, args = args, options = {poUsePath, poStdErrToStdOut}
  )

  engine.uciInitialize

proc newUciEngine*(
    command: string, args: openArray[string] = [], debug = false
): UciEngine =
  ## Convenience function to start and initialize an engine
  result = default UciEngine
  result.debug = debug
  result.start(command, args)

proc stop*(engine: var UciEngine) =
  ## Stop current search
  engine.sendCommand("stop")

proc quit*(engine: var UciEngine) =
  ## Stops the engine process.
  ## Only needs to be called if you want to stop the engine explicitly
  ## before going out of scope, otherwise engine deinitialization is
  ## automatically done by the destructor.

  if engine.initialized:
    engine.sendCommand("quit")
    engine.process.close()

  # Mark as moved to prevent destructor from running cleanup again
  wasMoved(engine)

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

proc go*(engine: var UciEngine, limit: Limit): PlayResult =
  ## Ask engine to search and return best move.
  ## Uses the previously set position state of the engine.
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

  if limit.movesToGo < limit.movesToGo.typeof.high:
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
        # 1. Parse the info line into a temporary object
        let newInfo = parseInfo(parts[1], engine.game.currentPosition())

        # 2. Determine the multipv key (defaults to 1)
        let multipvNumber = newInfo.multipv.get(otherwise = 1)

        # 3. Merge new info into the existing table entry
        var currentPvInfo = result.pvs.getOrDefault(multipvNumber)
        for newField, oldField in fields(newInfo, currentPvInfo):
          if newField.isSome:
            oldField = newField

        # Ensure the multipv number is set in the final object
        if currentPvInfo.multipv.isNone:
          currentPvInfo.multipv = some multipvNumber

        result.pvs[multipvNumber] = currentPvInfo
    of "bestmove":
      if parts.len > 1:
        let moveParts = parts[1].splitWhitespace()
        if moveParts.len > 0:
          try:
            result.move = moveParts[0].toMove(engine.game.currentPosition())

            # Check for ponder move
            if moveParts.len > 2 and moveParts[1] == "ponder":
              try:
                let ponderPos = engine.game.currentPosition().doMove(result.move)
                result.ponder = some moveParts[2].toMove(ponderPos)
              except ValueError:
                discard # Ignore invalid ponder move

            return
          except ValueError:
            # Engine returned an invalid move
            # This indicates an issue, so we should raise an exception.
            raise newException(ValueError, "Engine failed to return a valid bestmove.")

      # If bestmove line is malformed or has no move
      raise newException(ValueError, "Received malformed 'bestmove' from engine.")
    else:
      discard

proc play*(engine: var UciEngine, game: Game, limit: Limit): PlayResult =
  discard engine.isReady()
  engine.setPosition(game)
  engine.go(limit)

proc play*(engine: var UciEngine, position: Position, limit: Limit): PlayResult =
  discard engine.isReady()
  engine.setPosition(position)
  engine.go(limit)
