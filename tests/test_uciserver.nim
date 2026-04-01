import unittest, osproc, os
import nimchess/[uciclient, movegen, strchess, move, game]

const randomEngineSrc =
  currentSourcePath().parentDir / ".." / "examples" / "randomengine.nim"
const randomEngineBin = currentSourcePath().parentDir / "randomengine_testbin"

# Build the random engine before running tests
let (buildOutput, buildExitCode) = execCmdEx(
  "nim c -d:release --threads:on --path:" & currentSourcePath().parentDir / ".." / "src" &
    " -o:" & randomEngineBin & " " & randomEngineSrc
)
doAssert buildExitCode == 0, "Failed to build random engine:\n" & buildOutput

const testEngine = randomEngineBin

# Shared tests that work with any UCI engine
include shared_engine_tests

suite "UCI Server - fastchess compliance":
  test "fastchess --compliance":
    let (output, exitCode) = execCmdEx("fastchess --compliance " & randomEngineBin)
    if exitCode != 0:
      echo output
    check exitCode == 0

# Cleanup
removeFile(randomEngineBin)
