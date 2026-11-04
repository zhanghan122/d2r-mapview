
readLastGameName(ByRef d2rprocess, ByRef gameWindowId, ByRef offsets, ByRef session) {
    if (not WinExist(gameWindowId)) {
        WriteLog(gameWindowId " not found, please make sure game is running")
        if (session) {
            session.saveEntry()
        }
        ExitApp
    }
    ; gameData anchor optional: return empty without dereferencing BaseAddress+0.
    if (!offsets.HasKey("gameDataOffset") || offsets["gameDataOffset"] <= 0) {
        WriteLogDebug("readLastGameName skipped: gameData unresolved")
        return ""
    }
    gameNameOffset := offsets["gameDataOffset"] + 0x40
    gameNameAddress := d2rprocess.BaseAddress + gameNameOffset
    gameName := d2rprocess.readString(gameNameAddress, length := 0)
    return gameName
}
