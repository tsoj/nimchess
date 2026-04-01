## UCI protocol server implementation for chess engine authors.
##
## This module provides everything needed to make a chess engine speak UCI.
## The engine author provides callback functions for search, option handling,
## and new game events. The library handles all UCI protocol parsing,
## position management, and threading.
##
## The search handler runs in a separate thread and must:
## - Check ``stopFlag`` periodically and stop when it becomes true
## - Call ``sendUciInfo`` to report search progress
## - Call ``sendBestMove`` when the search is complete
##
## Example:
##
## .. code-block:: nim
##   import nimchess/uciserver
##
##   proc mySearch(params: GoParams) {.nimcall, gcsafe.} =
##     let position = params.game.currentPosition
##     # ... perform search, checking params.stopFlag[] periodically ...
##
##     sendBestMove(bestMove, position)
##
##   var server = newUciServer(
##     name = "MyEngine 1.0",
##     author = "Me",
##     onGo = mySearch,
##   )
##   server.uciLoop()

import std/[strutils, atomics, options]
import position, types, ucitypes, game, strchess, movegen

export ucitypes, game

type
  GoParams* = object ## Parameters passed to the search handler
    game*: Game ## Game state including position history, for repetition detection etc.
    searchMoves*: seq[Move] ## Moves to search (all legal moves if no restriction given)
    limit*: Limit ## Time, depth, and node limits
    ponder*: bool ## Pondering mode
    stopFlag*: ptr Atomic[bool] ## Check periodically; stop searching when true

  SearchHandler* = proc(params: GoParams) {.nimcall, gcsafe.}
    ## Search handler that runs in a separate thread.
    ## Must call ``sendBestMove`` when the search is complete.

  SetOptionHandler* = proc(name, value: string)
    ## Called when the GUI sends ``setoption name <name> value <value>``.
    ## For button-type options, value will be empty.

  NewGameHandler* = proc() ## Called when the GUI sends ``ucinewgame``.

  QuitHandler* = proc() ## Called when the GUI sends ``quit`` or EOF is reached.

  CommandHandler* = proc(game: var Game, params: seq[string])
    ## Handler for a custom command. Receives the current game state
    ## (mutable, so it can modify the position) and the command parameters.

  CustomCommand* = object ## A custom command registered with the server
    name*: string
    helpText*: string
    handler*: CommandHandler

  SearchThreadInput = object
    handler: SearchHandler
    params: GoParams
    searchRunningFlag: ptr Atomic[bool]

  UciServer* = object ## UCI server that manages the protocol loop
    name*: string
    author*: string
    options*: seq[EngineOption]
    game*: Game ## Current game state (public for custom command access)
    onGo*: SearchHandler
    onSetOption*: SetOptionHandler
    onNewGame*: NewGameHandler
    onQuit*: QuitHandler
    customCommands*: seq[CustomCommand]
    stopFlag: Atomic[bool]
    searchRunning: Atomic[bool]
    searchThread: ref Thread[SearchThreadInput]

func `=copy`*(dest: var UciServer, source: UciServer) {.error.}

# --- UCI output helpers ---
# These are safe to call from the search thread.

proc sendBestMove*(move: Move, position: Position, ponder = none(Move)) =
  ## Outputs a ``bestmove`` line. Call this from your search handler when done.
  var line = "bestmove " & move.toUCI(position)
  if ponder.isSome:
    let ponderPos = position.doMove(move)
    line &= " ponder " & ponder.get.toUCI(ponderPos)
  echo line

proc sendUciInfo*(info: UciInfo, position: Position) =
  ## Outputs an ``info`` line. Call this from your search handler to report progress.
  var line = "info"
  if info.depth.isSome:
    line &= " depth " & $info.depth.get
  if info.seldepth.isSome:
    line &= " seldepth " & $info.seldepth.get
  if info.multipv.isSome:
    line &= " multipv " & $info.multipv.get
  if info.score.isSome:
    line &= " score " & $info.score.get
  if info.nodes.isSome:
    line &= " nodes " & $info.nodes.get
  if info.nps.isSome:
    line &= " nps " & $info.nps.get
  if info.hashfull.isSome:
    line &= " hashfull " & $info.hashfull.get
  if info.tbhits.isSome:
    line &= " tbhits " & $info.tbhits.get
  if info.timeSeconds.isSome:
    line &= " time " & $(int(info.timeSeconds.get * 1000))
  if info.pv.isSome and info.pv.get.len > 0:
    line &= " pv " & info.pv.get.notation(position).strip()
  if info.string.isSome:
    line &= " string " & info.string.get
  echo line

proc sendInfoString*(s: string) =
  ## Outputs an ``info string`` line.
  echo "info string ", s

# --- Internal implementation ---

proc runSearchThread(input: SearchThreadInput) {.thread, nimcall.} =
  input.searchRunningFlag[].store(true)
  input.handler(input.params)
  input.searchRunningFlag[].store(false)

proc stopSearch(server: var UciServer) =
  server.stopFlag.store(true)
  if server.searchThread != nil:
    joinThread server.searchThread[]
  server.searchThread = nil

proc uciCommand(server: UciServer) =
  echo "id name ", server.name
  echo "id author ", server.author
  for opt in server.options:
    echo "option ", opt.formatOption()
  echo "uciok"

proc playMoves(server: var UciServer, params: seq[string]) =
  for param in params:
    server.game.addMove param

proc setPosition(server: var UciServer, params: seq[string]) =
  var
    index = 0
    position: Position

  if params.len >= 1 and params[0] == "startpos":
    position = classicalStartPos
    index = 1
  elif params.len >= 1 and params[0] == "fen":
    var fen = ""
    index = 1
    var numFenWords = 0
    while params.len > index and params[index] != "moves":
      if numFenWords < 6:
        numFenWords += 1
        fen &= " " & params[index]
      index += 1
    position = fen.toPosition
  else:
    sendInfoString "Unknown parameters"
    return

  server.game = newGame(startPosition = position)

  if params.len > index and params[index] == "moves":
    index += 1
    server.playMoves params[index .. ^1]

proc go(server: var UciServer, params: seq[string]) =
  var goParams =
    GoParams(game: server.game, limit: default(Limit), stopFlag: addr server.stopFlag)

  var hasSearchMoves = false

  for i in 0 ..< params.len:
    if i + 1 < params.len:
      try:
        case params[i]
        of "depth":
          goParams.limit.depth = params[i + 1].parseInt
        of "nodes":
          goParams.limit.nodes = params[i + 1].parseInt
        of "movetime":
          goParams.limit.movetimeSeconds = params[i + 1].parseFloat / 1000.0
        of "wtime":
          goParams.limit.whiteTimeSeconds = params[i + 1].parseFloat / 1000.0
        of "btime":
          goParams.limit.blackTimeSeconds = params[i + 1].parseFloat / 1000.0
        of "winc":
          goParams.limit.whiteIncSeconds = params[i + 1].parseFloat / 1000.0
        of "binc":
          goParams.limit.blackIncSeconds = params[i + 1].parseFloat / 1000.0
        of "movestogo":
          goParams.limit.movesToGo = params[i + 1].parseInt
        else:
          sendInfoString "Unknown parameters"
      except ValueError:
        sendInfoString "Unknown parameters"

    case params[i]
    of "ponder":
      goParams.ponder = true
    else:
      try:
        goParams.searchMoves.add params[i].toMove(server.game.currentPosition)
        hasSearchMoves = true
      except CatchableError:
        sendInfoString "Unknown parameters"

  if not hasSearchMoves:
    goParams.searchMoves = server.game.currentPosition.legalMoves

  server.stopSearch()

  doAssert server.searchThread == nil
  server.stopFlag.store(false)
  server.searchThread = new Thread[SearchThreadInput]
  createThread(
    server.searchThread[],
    runSearchThread,
    SearchThreadInput(
      handler: server.onGo,
      params: goParams,
      searchRunningFlag: addr server.searchRunning,
    ),
  )

# --- Help system ---

const builtinHelp = [
  ("uci", "Identify engine and list options, then send uciok."),
  ("isready", "Ping the engine; responds with readyok."),
  ("setoption", "setoption name <id> [value <x>] -- Set an engine option."),
  (
    "position",
    "position [fen <fenstring> | startpos] [moves <m1> ... <mN>] -- Set up a position.",
  ),
  (
    "go",
    "go [depth|nodes|movetime|wtime|btime|winc|binc|movestogo|ponder|infinite|searchmoves <x>]... -- Start searching.",
  ),
  ("stop", "Stop the current search."),
  ("quit", "Quit the engine."),
  ("ucinewgame", "Signal that the next search is from a different game."),
  ("ponderhit", "The expected ponder move was played."),
  ("print", "print [debug] -- Print the current board position."),
  ("fen", "Print the FEN of the current position."),
  (
    "moves",
    "moves <m1> ... <mN> -- Play moves on the current position. Accepts UCI and SAN notation.",
  ),
  ("help", "help [command] -- Show available commands or help for a specific command."),
]

proc printHelp(server: UciServer, params: seq[string]) =
  if params.len == 0:
    echo "Available commands:"
    for (name, _) in builtinHelp:
      echo "  ", name
    for cmd in server.customCommands:
      echo "  ", cmd.name
    echo "Use 'help <command>' for details."
  else:
    let target = params[0]
    for (name, text) in builtinHelp:
      if name == target:
        echo text
        return
    for cmd in server.customCommands:
      if cmd.name == target:
        echo cmd.helpText
        return
    echo "Unknown command: ", target

# --- Constructor ---

proc newUciServer*(
    name: string,
    author: string,
    options: openArray[EngineOption] = [],
    onGo: SearchHandler,
    onSetOption: SetOptionHandler = nil,
    onNewGame: NewGameHandler = nil,
    onQuit: QuitHandler = nil,
    customCommands: openArray[CustomCommand] = [],
): UciServer =
  ## Creates a new UCI server.
  result = UciServer(
    name: name,
    author: author,
    options: @options,
    onGo: onGo,
    onSetOption: onSetOption,
    onNewGame: onNewGame,
    onQuit: onQuit,
    customCommands: @customCommands,
    game: newGame(),
  )

# --- Main loop ---

proc uciLoop*(server: var UciServer) =
  ## Runs the main UCI protocol loop. Reads from stdin, dispatches commands,
  ## and runs the search handler in a separate thread. Blocks until ``quit``
  ## is received or EOF is reached.
  while true:
    try:
      let command = readLine(stdin)
      let params = command.splitWhitespace()
      if params.len == 0 or params[0] == "":
        continue

      case params[0]
      of "uci":
        server.uciCommand()
      of "isready":
        echo "readyok"
      of "setoption":
        if server.onSetOption != nil and params.len >= 3 and params[1] == "name":
          var nameEnd = params.len
          var valueStart = -1
          for i in 2 ..< params.len:
            if params[i] == "value" and i + 1 < params.len:
              nameEnd = i
              valueStart = i + 1
              break
          let optName = params[2 ..< nameEnd].join(" ")
          let optValue =
            if valueStart >= 0:
              params[valueStart ..^ 1].join(" ")
            else:
              ""
          server.onSetOption(optName, optValue)
      of "position":
        server.setPosition(params[1 ..^ 1])
      of "go":
        server.go(params[1 ..^ 1])
      of "stop":
        server.stopSearch()
      of "ucinewgame":
        if server.searchRunning.load:
          sendInfoString("Can't start new game while search is running")
        else:
          if server.onNewGame != nil:
            server.onNewGame()
      of "ponderhit":
        discard
      of "print":
        if params.len >= 2 and params[1] == "debug":
          echo server.game.currentPosition.debugString
        else:
          echo server.game.currentPosition
      of "fen":
        echo server.game.currentPosition.fen
      of "moves":
        try:
          server.playMoves(params[1 ..^ 1])
        except CatchableError:
          sendInfoString("Error: " & getCurrentExceptionMsg())
      of "help":
        server.printHelp(params[1 ..^ 1])
      of "quit":
        server.stopSearch()
        if server.onQuit != nil:
          server.onQuit()
        break
      else:
        # Check custom commands first
        var handled = false
        for cmd in server.customCommands:
          if params[0] == cmd.name:
            cmd.handler(server.game, params[1 ..^ 1])
            handled = true
            break

        if not handled:
          # Fallback: try parsing as moves, SAN moves, or FEN
          try:
            server.playMoves(params)
          except CatchableError:
            try:
              server.setPosition(@["fen"] & params)
            except CatchableError:
              sendInfoString("Unknown command: " & params[0])
    except EOFError:
      server.stopSearch()
      if server.onQuit != nil:
        server.onQuit()
      break
    except CatchableError:
      sendInfoString("Error: " & getCurrentExceptionMsg())
