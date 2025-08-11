import types, bitboard
export types, bitboard

type CastlingSide* = enum
  queenside
  kingside

func connectOnFile(a, b: Square): Bitboard =
  result = 0.Bitboard
  if not empty(rank(a) and rank(b)):
    var currentSquare = min(a, b)
    while true:
      result = result or currentSquare.toBitboard
      if currentSquare == max(a, b):
        break
      inc currentSquare

func blockSensitive(
    target: array[white .. black, array[CastlingSide, Square]]
): array[white .. black, array[CastlingSide, array[a1 .. h8, Bitboard]]] =
  result =
    default(array[white .. black, array[CastlingSide, array[a1 .. h8, Bitboard]]])

  for us in white .. black:
    for castlingSide in queenside .. kingside:
      for source in a1 .. h8:
        result[us][castlingSide][source] =
          connectOnFile(source, target[us][castlingSide])

const
  kingTargetTable =
    [white: [queenside: c1, kingside: g1], black: [queenside: c8, kingside: g8]]
  rookTargetTable =
    [white: [queenside: d1, kingside: f1], black: [queenside: d8, kingside: f8]]
  blockSensitiveRook = blockSensitive(rookTargetTable)
  blockSensitiveKing = blockSensitive(kingTargetTable)

func castlingKingTarget*(us: Color, castlingSide: CastlingSide): Square =
  kingTargetTable[us][castlingSide]

func castlingRookTarget*(us: Color, castlingSide: CastlingSide): Square =
  rookTargetTable[us][castlingSide]

func blockSensitive*(
    us: Color, castlingSide: CastlingSide, kingSource, rookSource: Square
): Bitboard =
  (
    blockSensitiveKing[us][castlingSide][kingSource] or
    blockSensitiveRook[us][castlingSide][rookSource]
  ) and not (kingSource.toBitboard or rookSource.toBitboard)

func checkSensitive*(
    us: Color, castlingSide: CastlingSide, kingSource: Square
): seq[Square] =
  const checkSensitive = block:
    var checkSensitive:
      array[white .. black, array[CastlingSide, array[a1 .. h8, seq[Square]]]]

    for color in white .. black:
      for castlingSide in queenside .. kingside:
        for kingSource in a1 .. h8:
          let b =
            blockSensitiveKing[color][castlingSide][kingSource] and
            # I don't need to check if the king will be in check after the move is done
            (
              kingSource.toBitboard or
              not kingTargetTable[color][castlingSide].toBitboard
            )
          for square in b:
            checkSensitive[color][castlingSide][kingSource].add(square)

    checkSensitive
  checkSensitive[us][castlingSide][kingSource]
