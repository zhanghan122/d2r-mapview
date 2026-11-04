#SingleInstance, Force
SendMode Input
SetWorkingDir, %A_ScriptDir%


readIPAddress(ByRef d2rprocess, ByRef gameWindowId, ByRef offsets, ByRef session) {
    if (not WinExist(gameWindowId)) {
        WriteLog(gameWindowId " not found, please make sure game is running")
        if (session) {
            session.saveEntry()
        }
        ExitApp
    }
    ; gameData anchor optional: return empty without dereferencing BaseAddress+0.
    if (!offsets.HasKey("gameDataOffset") || offsets["gameDataOffset"] <= 0) {
        WriteLogDebug("readIPAddress skipped: gameData unresolved")
        return ""
    }
    ipOffset := offsets["gameDataOffset"] + 0x1D0
    ipAddressAddress := d2rprocess.BaseAddress + ipOffset
    ipAddress := d2rprocess.readString(ipAddressAddress, length := 0)
    return ipAddress
}
