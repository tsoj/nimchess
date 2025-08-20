## UCI (Universal Chess Interface) engine communication module for nimchess
##
## This module provides functionality to communicate with chess engines
## that support the UCI protocol, allowing you to:
## - Start and configure engines
## - Send positions and get best moves
## - Perform analysis with configurable limits
## - Handle engine options and settings

import std/[osproc, streams, strutils, options, tables]
import position, move, types, strchess, movegen

type
  EngineError* = object of CatchableError ## Base exception for engine-related errors

  EngineTerminatedError* = object of EngineError
    ## Exception raised when engine process terminates unexpectedly

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

  PlayResult* = object ## Result from asking engine to play a move
    move*: Option[Move] ## Best move found
    ponder*: Option[Move] ## Expected opponent response
    info*: UciInfo ## Additional search information
    drawOffered*: bool ## Whether engine offered a draw
    resigned*: bool ## Whether engine resigned

  AnalysisResult* = ref object ## Handle for ongoing engine analysis
    info*: UciInfo
    multipv*: seq[UciInfo] ## Multiple PV lines
    stopped*: bool
    bestMove*: Option[Move]
    engine: UciEngine

  UciEngine* = ref object ## UCI chess engine communication handler
    process: Process
    options*: Table[string, EngineOption]
    id*: Table[string, string]
    initialized*: bool
    debug: bool
    currentPosition: Position

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

proc sendCommand(engine: UciEngine, command: string) =
  ## Send a command to the engine
  if engine.debug:
    echo ">> ", command
  engine.process.inputStream.writeLine(command)
  engine.process.inputStream.flush()

proc readLine(engine: UciEngine): string =
  ## Read a line from the engine
  result = engine.process.outputStream.readLine()
  if engine.debug and result.len > 0:
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
    raise newException(EngineError, "Unknown option type: " & optionType)

proc parseInfo*(line: string, position: Position): UciInfo =
  ## Parse a UCI info line
  let parts = line.split()
  var i = 0

  while i < parts.len:
    case parts[i]
    of "depth":
      i += 1
      if i < parts.len:
        result.depth = some(parseInt(parts[i]))
    of "seldepth":
      i += 1
      if i < parts.len:
        result.seldepth = some(parseInt(parts[i]))
    of "time":
      i += 1
      if i < parts.len:
        result.time = some(parseInt(parts[i]).float / 1000.0)
    of "nodes":
      i += 1
      if i < parts.len:
        result.nodes = some(parseInt(parts[i]))
    of "nps":
      i += 1
      if i < parts.len:
        result.nps = some(parseInt(parts[i]))
    of "score":
      i += 1
      if i + 1 < parts.len:
        case parts[i]
        of "cp":
          i += 1
          result.score = some(Score(kind: skCp, cp: parseInt(parts[i])))
        of "mate":
          i += 1
          let mateVal = parseInt(parts[i])
          if mateVal == 0:
            result.score = some(Score(kind: skMateGiven))
          else:
            result.score = some(Score(kind: skMate, mate: mateVal))
    of "pv":
      i += 1
      result.pv = some newSeq[Move]()
      var tempPos = position
      while i < parts.len:
        let move = parts[i].toMove(tempPos)
        if move.isNoMove:
          break
        if tempPos.isLegal(move):
          result.pv.get.add(move)
          tempPos = tempPos.doMove(move)
        else:
          break
        i += 1
      continue
    of "multipv":
      i += 1
      if i < parts.len:
        result.multipv = some(parseInt(parts[i]))
    of "currmove":
      i += 1
      if i < parts.len:
        let move = parts[i].toMove(position)
        if not move.isNoMove:
          result.currmove = some(move)
    of "currmovenumber":
      i += 1
      if i < parts.len:
        result.currmovenumber = some(parseInt(parts[i]))
    of "hashfull":
      i += 1
      if i < parts.len:
        result.hashfull = some(parseInt(parts[i]))
    of "tbhits":
      i += 1
      if i < parts.len:
        result.tbhits = some(parseInt(parts[i]))
    of "string":
      i += 1
      if i < parts.len:
        result.string = some(parts[i ..^ 1].join(" "))
      break
    i += 1

# Main engine interface

proc newUciEngine*(): UciEngine =
  ## Create a new UCI engine handler (without starting a process)
  result = UciEngine(
    options: initTable[string, EngineOption](),
    id: initTable[string, string](),
    initialized: false,
    debug: false,
  )

proc initialize(engine: UciEngine) =
  ## Initialize the UCI engine
  if engine.initialized:
    raise newException(EngineError, "Engine already initialized")

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
      engine.initialized = true
      return
    else:
      discard

proc start*(engine: UciEngine, command: string, args: openArray[string] = []) =
  ## Start the engine process
  var allArgs = @[command]
  allArgs.add(args)

  engine.process = startProcess(
    command = command, args = args, options = {poUsePath, poStdErrToStdOut}
  )

  engine.initialize

proc setOption*(engine: UciEngine, name: string, value: string) =
  ## Set an engine option
  if not engine.initialized:
    raise newException(EngineError, "Engine not initialized")

  let cmd = "setoption name " & name & " value " & value
  engine.sendCommand(cmd)

proc isReady*(engine: UciEngine): bool =
  ## Check if engine is ready
  engine.sendCommand("isready")

  let line = engine.readLine()
  return line == "readyok"

proc newGame*(engine: UciEngine) =
  ## Signal a new game to the engine
  if not engine.initialized:
    raise newException(EngineError, "Engine not initialized")

  engine.sendCommand("ucinewgame")

proc setPosition*(engine: UciEngine, position: Position, moves: seq[Move] = @[]) =
  ## Set the current position
  engine.currentPosition = position

  # Check if this is the starting position
  let startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  var cmd = ""

  if position.fen() == startingFen and moves.len == 0:
    cmd = "position startpos"
  else:
    cmd = "position fen " & position.fen()

  if moves.len > 0:
    cmd.add(" moves")
    for move in moves:
      cmd.add(" " & $move)

  engine.sendCommand(cmd)

proc go*(engine: UciEngine, limit: Limit): PlayResult =
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

    let parts = line.split(maxsplit = 1)
    if parts.len == 0:
      continue

    case parts[0]
    of "info":
      if parts.len > 1:
        let info = parseInfo(parts[1], engine.currentPosition)
        for infoOpt, resultOpt in fields(info, result.info):
          if infoOpt.isSome:
            resultOpt = infoOpt
    of "bestmove":
      if parts.len > 1:
        let moveParts = parts[1].split()
        if moveParts.len > 0 and moveParts[0] != "(none)":
          let move = moveParts[0].toMove(engine.currentPosition)
          if not move.isNoMove:
            result.move = some(move)

          # Check for ponder move
          if moveParts.len > 2 and moveParts[1] == "ponder":
            let ponderMove = moveParts[2].toMove(engine.currentPosition.doMove(move))
            if not ponderMove.isNoMove:
              result.ponder = some(ponderMove)

      break
    else:
      discard

proc stop*(engine: UciEngine) =
  ## Stop current search
  engine.sendCommand("stop")

proc quit*(engine: UciEngine) =
  ## Quit the engine
  if engine.initialized:
    engine.sendCommand("quit")

  if not engine.process.isNil:
    engine.process.close()

proc close*(engine: UciEngine) =
  ## Close the engine process
  engine.quit()

# High-level convenience functions

proc play*(
    engine: UciEngine, position: Position, limit: Limit, moves: seq[Move] = @[]
): PlayResult =
  ## High-level function to get best move for a position
  if not engine.initialized:
    engine.initialize()

  discard engine.isReady()
  engine.setPosition(position, moves)
  result = engine.go(limit)

proc startEngine*(command: string, args: openArray[string] = []): UciEngine =
  ## Convenience function to start and initialize an engine
  result = newUciEngine()
  result.start(command, args)
  result.initialize()

# Example usage functions (commented out for library)
when isMainModule:
  proc example() =
    ## Example of how to use the engine
    try:
      let engine = startEngine("stockfish")

      # Set some options
      engine.setOption("Threads", "4")
      engine.setOption("Hash", "128")

      # Create a starting position
      let position =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition
      let limit = Limit(movetimeSeconds: 5.0)

      # Get best move
      let result = engine.play(position, limit)

      if result.move.isSome:
        echo "Best move: ", result.move.get()

      echo result.info

      engine.quit()
    except EngineError as e:
      echo "Engine error: ", e.msg
    except Exception as e:
      echo "Error: ", e.msg

  example()
