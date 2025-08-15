import position, strchess, move, movegen
export position

func generateMovesViaPseudoLegalText(
    position: Position, moves: var openArray[Move]
): int =
  static:
    assert sizeof(uint16) == sizeof(Move)
  result = 0
  for i in uint16.low .. uint16.high:
    let move = cast[Move](i)
    if position.isPseudoLegal(move):
      moves[result] = move
      result += 1

func perft*(
    position: Position,
    depth: int,
    printRootMoveNodes: static bool = false,
    usePseudoLegalTest: static bool = false,
): int64 =
  if depth <= 0:
    return 1
  var moves: array[320, Move]
  let numMoves =
    when usePseudoLegalTest:
      position.generateMovesViaPseudoLegalText(moves)
    else:
      position.generateMoves(moves)
  assert numMoves < 320
  for move in moves[0 ..< numMoves]:
    let newPosition = position.doMove(move)
    if not newPosition.inCheck(position.us):
      let nodes = newPosition.perft(depth - 1, usePseudoLegalTest = usePseudoLegalTest)
      when printRootMoveNodes:
        debugEcho "    ", move, " ", nodes, " ", newPosition.fen
      result += nodes
