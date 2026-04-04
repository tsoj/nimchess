import std/[options, tables]
import types, move

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
    movetimeSeconds*: Option[float] ## Search exactly this many seconds
    depth*: int = int.high ## Search to this depth only
    nodes*: int = int.high ## Search only this many nodes
    timeSeconds*: array[white .. black, float] = [float.high, float.high]
      ## Time remaining per color (seconds)
    incSeconds*: array[white .. black, float] = [0.0, 0.0]
      ## Increment per move per color (seconds)
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

func formatOption*(option: EngineOption): string =
  ## Formats an EngineOption as a UCI "option" line (without the "option " prefix).
  result = "name " & option.name & " type " & $option.kind
  case option.kind
  of eotCheck:
    result &= " default " & $option.defaultBool
  of eotSpin:
    result &=
      " default " & $option.defaultInt & " min " & $option.minVal & " max " &
      $option.maxVal
  of eotCombo:
    result &= " default " & option.defaultStr
    for choice in option.choices:
      result &= " var " & choice
  of eotButton:
    discard
  of eotString:
    result &= " default " & option.defaultString
