import position, move
import std/tables

export position, move
export tables

type Game* = object
  headers*: Table[string, string]
  moves*: seq[Move]
  startPosition*: Position
  result*: string

func positions(game: Game): seq[Position] =
  result = @[game.startPosition]
  for move in game.moves:
    result.add result[^1].doMove(move)
