

PatternScan(ByRef d2r, ByRef offsets) {
    SetFormat, Integer, Hex
    failedAnchors := ""
    ; unit table
    pattern := d2r.hexStringToPattern("48 03 C7 49 8B 8C C6")
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "unitTable", patternAddress)) {
        unitTable := d2r.read(patternAddress + 7, "Int")
        offsets["unitTable"] := unitTable
        WriteLog("Scanned and found unitTable offset: 0x" . Format("{:X}", unitTable + 0))
    } else {
        failedAnchors .= " unitTable"
    }
    
    ; ui
    pattern := d2r.hexStringToPattern("40 84 ed 0f 94 05")
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "ui", patternAddress)) {
        offsetBuffer := d2r.read(patternAddress + 6, "Int")
        uiOffset := ((patternAddress - d2r.BaseAddress) + 10 + offsetBuffer)
        offsets["uiOffset"] := uiOffset
        WriteLog("Scanned and found UI offset: 0x" . Format("{:X}", uiOffset + 0))
    } else {
        failedAnchors .= " ui"
    }

    ; expansion
    pattern := d2r.hexStringToPattern("48 8B 05 ?? ?? ?? ?? 48 8B D9 F3 0F 10 50 ??")
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "expansion", patternAddress)) {
        offsetBuffer := d2r.read(patternAddress + 3, "Int")
        expOffset := ((patternAddress - d2r.BaseAddress) + 7 + offsetBuffer)
        offsets["expOffset"] := expOffset
        WriteLog("Scanned and found expansion offset: 0x" . Format("{:X}", expOffset + 0))
    } else {
        WriteLog("ANCHOR OPTIONAL-MISSING: expansion - continuing without expOffset")
    }

    ; game data (IP and name) 
    pattern := d2r.hexStringToPattern("44 88 25 ?? ?? ?? ?? 66 44 89 25 ?? ?? ?? ??")
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "gameData", patternAddress)) {
        offsetBuffer := d2r.read(patternAddress + 0x3, "Int")
        gameDataOffset := ((patternAddress - d2r.BaseAddress) - 0x121 + offsetBuffer)
        offsets["gameDataOffset"] := gameDataOffset
        WriteLog("Scanned and found game data offset: 0x" . Format("{:X}", gameDataOffset + 0))
    } else {
        WriteLog("ANCHOR OPTIONAL-MISSING: gameData - continuing without gameDataOffset")
    }

    ; menu visibility    
    pattern := d2r.hexStringToPattern("8B 05 ?? ?? ?? ?? 89 44 24 20 74 07") 
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "menu", patternAddress)) {
        offsetBuffer := d2r.read(patternAddress + 2, "Int")
        menuOffset := ((patternAddress - d2r.BaseAddress) + 6 + offsetBuffer)
        offsets["menuOffset"] := menuOffset
        WriteLog("Scanned and found menu offset: 0x" . Format("{:X}", menuOffset + 0))
    } else {
        failedAnchors .= " menu"
    }

    ; last hover object
    pattern := d2r.hexStringToPattern("C6 84 C2 ?? ?? ?? ?? ?? 48 8B 74 24 ??") 
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "hover", patternAddress)) {
        hoverOffset := d2r.read(patternAddress + 3, "Int") - 1
        offsets["hoverOffset"] := hoverOffset
        WriteLog("Scanned and found hover offset: 0x" . Format("{:X}", hoverOffset + 0))
    } else {
        failedAnchors .= " hover"
    }

    ; roster
    pattern := d2r.hexStringToPattern("02 45 33 D2 4D 8B") 
    patternAddress := d2r.modulePatternScan("D2R.exe", , pattern*)
    ; P0: fail closed - never derive an offset from a failed scan.
    if (AnchorFound(d2r, "roster", patternAddress)) {
        offsetBuffer := d2r.read(patternAddress - 3, "Int")
        rosterOffset := ((patternAddress - d2r.BaseAddress) + 1 + offsetBuffer)
        offsets["rosterOffset"] := rosterOffset
        WriteLog("Scanned and found roster offset: 0x" . Format("{:X}", rosterOffset + 0))
    } else {
        WriteLog("ANCHOR OPTIONAL-MISSING: roster - continuing without rosterOffset")
    }

    ; P0: a missing required anchor means every derived offset is garbage, so stop here.
    if (failedAnchors != "") {
        WriteLog("ANCHOR RESULT: FAILED ->" failedAnchors)
        ScanDiagnostics(d2r)
        Msgbox, 48, d2r-mapview, Memory anchors not found:%failedAnchors%`n`nThis game build is probably unsupported.`nDetails were written to:`n%A_ScriptDir%\log.txt`n`nThe overlay will now exit.
        ExitApp
    }
    WriteLog("ANCHOR RESULT: OK (required 4/4; roster/gameData/expansion optional)")
}

; P0: log every anchor result, including the module-relative RVA.
AnchorFound(ByRef d2r, anchorName, patternAddress) {
    if (patternAddress > 0) {
        WriteLog("ANCHOR OK: " . anchorName . " at 0x" . Format("{:X}", patternAddress + 0) . " (RVA 0x" . Format("{:X}", (patternAddress - d2r.BaseAddress) + 0) . ")")
        return true
    }
    WriteLog("ANCHOR FAIL: " anchorName " - modulePatternScan returned '" patternAddress "'")
    return false
}

; P0: on failure, record module/region facts instead of guessing offsets.
ScanDiagnostics(ByRef d2r) {
    WriteLog("--- ANCHOR DIAGNOSTICS START ---")
    WriteLog("BaseAddress: 0x" . Format("{:X}", d2r.BaseAddress + 0))
    moduleInfo := ""
    moduleBase := d2r.getModuleBaseAddress("D2R.exe", moduleInfo)
    if (moduleBase > 0) {
        WriteLog("D2R.exe module base: 0x" . Format("{:X}", moduleInfo.lpBaseOfDll + 0))
        WriteLog("D2R.exe module size: 0x" . Format("{:X}", moduleInfo.SizeOfImage + 0))
        headerRead := d2r.readRaw(moduleInfo.lpBaseOfDll, probeBuffer, 16)
        WriteLog("Module header readable: " . (headerRead ? "yes" : "no"))
        ; Count private executable regions - code outside the image defeats image scans.
        address := moduleInfo.lpBaseOfDll
        endAddress := address + moduleInfo.SizeOfImage
        region := ""
        regionCount := 0
        privateExecCount := 0
        while (address < endAddress) {
            if (!d2r.VirtualQueryEx(address, region))
                break
            regionCount += 1
            if (region.State = 0x1000 and region.Type = 0x20000 and (region.Protect & 0xF0))
                privateExecCount += 1
            if (region.RegionSize < 1)
                break
            address += region.RegionSize
        }
        WriteLog("Regions visited: " regionCount ", private executable: " privateExecCount)
    } else {
        WriteLog("D2R.exe module lookup failed: " moduleBase)
    }
    WriteLog("--- ANCHOR DIAGNOSTICS END ---")
}
