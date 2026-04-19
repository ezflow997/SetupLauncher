#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Match LiveView's DPI awareness so coordinate systems align for window positioning
try DllCall("SetThreadDpiAwarenessContext", "Ptr", -3)

; ============================================================================
; Setup Launcher - Application Setup Manager
; Opens apps via .lnk shortcuts and navigates menus with key sequences
; ============================================================================

global APP_NAME := "Setup Launcher"
global INI_FILE := A_ScriptDir "\SetupLauncher.ini"
global LOG_FILE := A_ScriptDir "\SetupLauncher.log"
global LOG_MAX_SIZE := 512 * 1024  ; 512 KB max before rotation
global Setups := []
global MonitorTimers := Map()
global SetupStatuses := Map()
global MonitoredTitles := Map()
global MonitoredHwnds := Map()
global HiddenPositions := Map()
global SetupHidden := Map()
global DwmKeepAliveThumbs := Map()  ; DWM thumbnail handles to keep rendering alive
global DwmKeepAliveGui := ""        ; Hidden GUI that hosts keep-alive thumbnails
global SetupRunning := false        ; Flag to prevent timer callbacks during setup launch

; Pause state
global Paused := false

; Main GUI controls
global MainGui := ""
global MainLV := ""
global BtnAdd := ""
global BtnEdit := ""
global BtnDelete := ""
global BtnRun := ""
global BtnStop := ""
global BtnRunAll := ""
global BtnClose := ""
global BtnCloseAll := ""
global BtnStopAll := ""
global BtnPause := ""
global BtnMoveUp := ""
global BtnMoveDown := ""
global BtnHideToggle := ""
global BtnHelp := ""
global TxtRefreshLabel := ""
global EdRefreshInterval := ""
global BtnRefreshStart := ""
global BtnRefreshStop := ""
global BtnRefreshDisplay := ""
global TxtStatusBar := ""

; Refresh cycle
global RefreshInterval := 300
global RefreshTimerFn := ""
global RefreshCountdownFn := ""
global RefreshSecondsLeft := 0
global RefreshCount := 0
global RefreshActive := false
global AutoRefresh := 0
global GlobalAutoStart := 1
global AutoShowCountdown := 0
global AutoHideCountdown := 0
global ChkAutoRefresh := ""
global ChkGlobalAutoStart := ""
global ChkAutoShowCountdown := ""
global ChkAutoHideCountdown := ""

; Floating countdown
global CountdownGui := ""
global CountdownTxtTime := ""
global CountdownTxtCount := ""
global CountdownVisible := false
global CountdownHidden := false
global CountdownSavedPos := ""

; Editor
global EditorOpen := false
global EditorGui := ""
global StepEditorGui := ""
global EdStepLV := ""
global EdRefreshStepLV := ""
global EditingIndex := 0
global EditingStepIndex := 0
global TempSteps := []
global TempRefreshSteps := []
global EditingRefreshStep := false

; ============================================================================
; Data Classes
; ============================================================================
class SetupData {
    __New() {
        this.Name := ""
        this.ShortcutPath := ""
        this.WindowTitle := ""
        this.AutoStart := 0
        this.KeepActive := 0
        this.CheckInterval := 5000
        this.CheckNet := 0
        this.NetAddress := ""
        this.NetPort := ""
        this.NetTimeout := 30
        this.NetRetryDelay := 5
        this.HideWindow := 0
        this.CloseBatchTitle := ""
        this.LastTitle := ""
        this.Steps := []
        this.RefreshSteps := []
    }
}

class StepData {
    __New() {
        this.Key := ""
        this.Mode := "delay"
        this.Value := "500"
    }
}

; ============================================================================
; Logging
; ============================================================================
LogInfo(msg) {
    WriteLog("INFO", msg)
}

LogError(msg) {
    WriteLog("ERROR", msg)
}

WriteLog(level, msg) {
    global LOG_FILE, LOG_MAX_SIZE
    try {
        ; Rotate if over max size
        if FileExist(LOG_FILE) {
            size := FileGetSize(LOG_FILE)
            if (size > LOG_MAX_SIZE) {
                oldFile := LOG_FILE ".old"
                if FileExist(oldFile)
                    FileDelete(oldFile)
                FileMove(LOG_FILE, oldFile)
            }
        }
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend(timestamp " [" level "] " msg "`n", LOG_FILE)
    }
}

; ============================================================================
; INI Load / Save
; ============================================================================
LoadAllSetups() {
    global Setups, RefreshInterval, AutoRefresh, GlobalAutoStart, AutoShowCountdown, AutoHideCountdown
    Setups := []

    if !FileExist(INI_FILE)
        return

    ; Load global settings
    RefreshInterval := Integer(IniRead(INI_FILE, "Global", "RefreshInterval", "300"))
    AutoRefresh := Integer(IniRead(INI_FILE, "Global", "AutoRefresh", "0"))
    GlobalAutoStart := Integer(IniRead(INI_FILE, "Global", "GlobalAutoStart", "1"))
    AutoShowCountdown := Integer(IniRead(INI_FILE, "Global", "AutoShowCountdown", "0"))
    AutoHideCountdown := Integer(IniRead(INI_FILE, "Global", "AutoHideCountdown", "0"))

    idx := 1
    Loop {
        section := "Setup_" idx
        name := IniRead(INI_FILE, section, "Name", "")
        if (name = "")
            break

        setup := SetupData()
        setup.Name := name
        setup.ShortcutPath := IniRead(INI_FILE, section, "ShortcutPath", "")
        setup.WindowTitle := IniRead(INI_FILE, section, "WindowTitle", "")
        setup.AutoStart := Integer(IniRead(INI_FILE, section, "AutoStart", "0"))
        setup.KeepActive := Integer(IniRead(INI_FILE, section, "KeepActive", "0"))
        setup.CheckInterval := Integer(IniRead(INI_FILE, section, "CheckInterval", "5000"))
        setup.CheckNet := Integer(IniRead(INI_FILE, section, "CheckNet", "0"))
        setup.NetAddress := IniRead(INI_FILE, section, "NetAddress", "")
        setup.NetPort := IniRead(INI_FILE, section, "NetPort", "")
        setup.NetTimeout := Integer(IniRead(INI_FILE, section, "NetTimeout", "30"))
        setup.NetRetryDelay := Integer(IniRead(INI_FILE, section, "NetRetryDelay", "5"))
        setup.HideWindow := Integer(IniRead(INI_FILE, section, "HideWindow", "0"))
        setup.CloseBatchTitle := IniRead(INI_FILE, section, "CloseBatchTitle", "")
        setup.LastTitle := IniRead(INI_FILE, section, "LastTitle", "")

        ; Navigation steps
        stepCount := Integer(IniRead(INI_FILE, section, "StepCount", "0"))
        setup.Steps := []
        Loop stepCount {
            step := StepData()
            step.Key := IniRead(INI_FILE, section, "Step_" A_Index "_Key", "")
            step.Mode := IniRead(INI_FILE, section, "Step_" A_Index "_Mode", "delay")
            step.Value := IniRead(INI_FILE, section, "Step_" A_Index "_Value", "500")
            setup.Steps.Push(step)
        }

        ; Refresh steps
        rStepCount := Integer(IniRead(INI_FILE, section, "RefreshStepCount", "0"))
        setup.RefreshSteps := []
        Loop rStepCount {
            step := StepData()
            step.Key := IniRead(INI_FILE, section, "RefreshStep_" A_Index "_Key", "")
            step.Mode := IniRead(INI_FILE, section, "RefreshStep_" A_Index "_Mode", "delay")
            step.Value := IniRead(INI_FILE, section, "RefreshStep_" A_Index "_Value", "500")
            setup.RefreshSteps.Push(step)
        }

        Setups.Push(setup)
        SetupStatuses[idx] := "Stopped"
        idx++
    }
}

SaveAllSetups() {
    global RefreshInterval, AutoRefresh, GlobalAutoStart, AutoShowCountdown, AutoHideCountdown

    ; Prevent timer interrupts during save to avoid partial/corrupt writes
    Critical("On")
    try {
    if FileExist(INI_FILE)
        FileDelete(INI_FILE)
    LogInfo("Saving " Setups.Length " setups to INI")

    ; Save global settings
    IniWrite(RefreshInterval, INI_FILE, "Global", "RefreshInterval")
    IniWrite(AutoRefresh, INI_FILE, "Global", "AutoRefresh")
    IniWrite(GlobalAutoStart, INI_FILE, "Global", "GlobalAutoStart")
    IniWrite(AutoShowCountdown, INI_FILE, "Global", "AutoShowCountdown")
    IniWrite(AutoHideCountdown, INI_FILE, "Global", "AutoHideCountdown")

    for idx, setup in Setups {
        section := "Setup_" idx
        IniWrite(setup.Name, INI_FILE, section, "Name")
        IniWrite(setup.ShortcutPath, INI_FILE, section, "ShortcutPath")
        IniWrite(setup.WindowTitle, INI_FILE, section, "WindowTitle")
        IniWrite(setup.AutoStart, INI_FILE, section, "AutoStart")
        IniWrite(setup.KeepActive, INI_FILE, section, "KeepActive")
        IniWrite(setup.CheckInterval, INI_FILE, section, "CheckInterval")
        IniWrite(setup.CheckNet, INI_FILE, section, "CheckNet")
        IniWrite(setup.NetAddress, INI_FILE, section, "NetAddress")
        IniWrite(setup.NetPort, INI_FILE, section, "NetPort")
        IniWrite(setup.NetTimeout, INI_FILE, section, "NetTimeout")
        IniWrite(setup.NetRetryDelay, INI_FILE, section, "NetRetryDelay")
        IniWrite(setup.HideWindow, INI_FILE, section, "HideWindow")
        IniWrite(setup.CloseBatchTitle, INI_FILE, section, "CloseBatchTitle")
        IniWrite(setup.LastTitle, INI_FILE, section, "LastTitle")

        ; Navigation steps
        IniWrite(setup.Steps.Length, INI_FILE, section, "StepCount")
        for sIdx, step in setup.Steps {
            IniWrite(step.Key, INI_FILE, section, "Step_" sIdx "_Key")
            IniWrite(step.Mode, INI_FILE, section, "Step_" sIdx "_Mode")
            IniWrite(step.Value, INI_FILE, section, "Step_" sIdx "_Value")
        }

        ; Refresh steps
        IniWrite(setup.RefreshSteps.Length, INI_FILE, section, "RefreshStepCount")
        for sIdx, step in setup.RefreshSteps {
            IniWrite(step.Key, INI_FILE, section, "RefreshStep_" sIdx "_Key")
            IniWrite(step.Mode, INI_FILE, section, "RefreshStep_" sIdx "_Mode")
            IniWrite(step.Value, INI_FILE, section, "RefreshStep_" sIdx "_Value")
        }
    }
    } catch as e {
        LogError("SaveAllSetups failed: " e.Message)
        throw
    } finally {
        Critical("Off")
    }
}

; ============================================================================
; Main GUI
; ============================================================================
BuildMainGui() {
    global MainGui, MainLV, BtnAdd, BtnEdit, BtnDelete, BtnMoveUp, BtnMoveDown, BtnRun, BtnStop, BtnRunAll
    global BtnClose, BtnCloseAll, BtnStopAll, BtnPause, BtnHideToggle, BtnHelp
    global ChkGlobalAutoStart, GlobalAutoStart
    global ChkAutoShowCountdown, AutoShowCountdown, ChkAutoHideCountdown, AutoHideCountdown
    global TxtRefreshLabel, EdRefreshInterval, BtnRefreshStart, BtnRefreshStop, BtnRefreshDisplay
    global TxtStatusBar, RefreshInterval, ChkAutoRefresh, AutoRefresh

    MainGui := Gui("+Resize +MinSize700x600", APP_NAME)
    MainGui.SetFont("s10", "Segoe UI")
    MainGui.BackColor := "FFFFFF"
    MainGui.MarginX := 15
    MainGui.MarginY := 10

    ; Header
    MainGui.SetFont("s14 Bold", "Segoe UI")
    MainGui.AddText("xm ym w600", APP_NAME)
    MainGui.SetFont("s10 Norm", "Segoe UI")
    MainGui.AddText("xm y+2 w600 cGray", "Manage application setups with automatic key navigation")

    ; ListView
    MainLV := MainGui.AddListView("xm y+10 w670 h200 Grid NoSortHdr +LV0x10000", ["#", "Name", "Shortcut", "Auto-Start", "Keep Active", "Status"])
    MainLV.ModifyCol(1, 30)
    MainLV.ModifyCol(2, 140)
    MainLV.ModifyCol(3, 180)
    MainLV.ModifyCol(4, 80)
    MainLV.ModifyCol(5, 80)
    MainLV.ModifyCol(6, 150)
    MainLV.OnEvent("DoubleClick", OnMainLVDoubleClick)

    ; Button row 1: setup management
    BtnAdd := MainGui.AddButton("xm y+10 w80 h32", "Add")
    BtnAdd.OnEvent("Click", OnAddSetup)

    BtnEdit := MainGui.AddButton("x+8 yp w80 h32", "Edit")
    BtnEdit.OnEvent("Click", OnEditSetup)

    BtnDelete := MainGui.AddButton("x+8 yp w80 h32", "Delete")
    BtnDelete.OnEvent("Click", OnDeleteSetup)

    BtnMoveUp := MainGui.AddButton("x+8 yp w32 h32", Chr(0x25B2))
    BtnMoveUp.OnEvent("Click", OnMoveSetupUp)

    BtnMoveDown := MainGui.AddButton("x+4 yp w32 h32", Chr(0x25BC))
    BtnMoveDown.OnEvent("Click", OnMoveSetupDown)

    BtnRun := MainGui.AddButton("x+25 yp w80 h32", "Run")
    BtnRun.OnEvent("Click", OnRunSetup)

    BtnStop := MainGui.AddButton("x+8 yp w80 h32", "Stop")
    BtnStop.OnEvent("Click", OnStopSetup)

    BtnRunAll := MainGui.AddButton("x+25 yp w130 h32", "Run Auto-Start")
    BtnRunAll.OnEvent("Click", OnRunAllAutoStart)

    ; Button row 2: Close, Close All, Pause
    BtnClose := MainGui.AddButton("xm y+8 w80 h32", "Close")
    BtnClose.OnEvent("Click", OnCloseSetup)

    BtnCloseAll := MainGui.AddButton("x+8 yp w90 h32", "Close All")
    BtnCloseAll.OnEvent("Click", OnCloseAllSetups)

    BtnStopAll := MainGui.AddButton("x+8 yp w80 h32", "Stop All")
    BtnStopAll.OnEvent("Click", OnStopAllSetups)

    BtnPause := MainGui.AddButton("x+25 yp w90 h32", "Pause All")
    BtnPause.OnEvent("Click", OnTogglePause)

    BtnHideToggle := MainGui.AddButton("x+8 yp w90 h32", "Hide/Show")
    BtnHideToggle.OnEvent("Click", OnToggleHide)

    BtnHelp := MainGui.AddButton("x+8 yp w32 h32", "?")
    BtnHelp.OnEvent("Click", OnShowHelp)

    ; Row 3: refresh controls
    TxtRefreshLabel := MainGui.AddText("xm y+10 w110 h24 +0x200", "Refresh (sec):")
    EdRefreshInterval := MainGui.AddEdit("x+5 yp w60 h24 Number vEdRefreshInt", String(RefreshInterval))

    BtnRefreshStart := MainGui.AddButton("x+10 yp-1 w100 h26", "Start Refresh")
    BtnRefreshStart.OnEvent("Click", OnStartRefresh)

    BtnRefreshStop := MainGui.AddButton("x+5 yp w100 h26", "Stop Refresh")
    BtnRefreshStop.OnEvent("Click", OnStopRefresh)

    BtnRefreshDisplay := MainGui.AddButton("x+5 yp w110 h26", "Show Display")
    BtnRefreshDisplay.OnEvent("Click", OnToggleDisplay)

    ; Row 3: toggles
    ChkGlobalAutoStart := MainGui.AddCheckbox("xm y+8 vChkGlobalAutoStart", "Run Auto-Start on script launch")
    ChkGlobalAutoStart.Value := GlobalAutoStart
    ChkGlobalAutoStart.OnEvent("Click", OnGlobalAutoStartToggle)

    ChkAutoRefresh := MainGui.AddCheckbox("x+20 yp vChkAutoRefresh", "Auto-start refresh after all setups finish")
    ChkAutoRefresh.Value := AutoRefresh
    ChkAutoRefresh.OnEvent("Click", OnAutoRefreshToggle)

    ; Row 4: countdown toggles
    ChkAutoShowCountdown := MainGui.AddCheckbox("xm y+6 vChkAutoShowCountdown", "Auto-show refresh timer")
    ChkAutoShowCountdown.Value := AutoShowCountdown
    ChkAutoShowCountdown.OnEvent("Click", OnAutoShowCountdownToggle)

    ChkAutoHideCountdown := MainGui.AddCheckbox("x+20 yp vChkAutoHideCountdown", "Auto-hide refresh timer")
    ChkAutoHideCountdown.Value := AutoHideCountdown
    ChkAutoHideCountdown.OnEvent("Click", OnAutoHideCountdownToggle)

    ; Status bar
    TxtStatusBar := MainGui.AddText("xm y+8 w670 h22 +0x200 cGray BackgroundF0F0F0", "  Refresh: Off")

    ; Events
    MainGui.OnEvent("Close", OnMainClose)
    MainGui.OnEvent("Size", OnMainResize)
}

RefreshMainLV() {
    global MainLV, Setups, SetupStatuses
    MainLV.Delete()

    for idx, setup in Setups {
        shortcutName := ""
        if (setup.ShortcutPath != "") {
            SplitPath(setup.ShortcutPath, &shortcutName)
        }
        autoStr := setup.AutoStart ? "Yes" : "No"
        keepStr := setup.KeepActive ? "Yes" : "No"
        status := SetupStatuses.Has(idx) ? SetupStatuses[idx] : "Stopped"
        MainLV.Add("", idx, setup.Name, shortcutName, autoStr, keepStr, status)
    }
}

OnMainResize(thisGui, minMax, width, height) {
    if (minMax = -1)
        return

    mx := 15
    lvW := width - (mx * 2)

    ; Bottom-up layout with explicit heights:
    ;   Status bar:   22px, 8px bottom margin
    ;   Checkbox 2:   22px, 6px gap above (auto-show/hide countdown)
    ;   Checkbox 1:   22px, 6px gap above (auto-start, auto-refresh)
    ;   Refresh row:  26px, 8px gap above
    ;   Button row 2: 32px, 8px gap above (Close, Close All, Pause)
    ;   Button row 1: 32px, 10px gap above (Add, Edit, Delete, Run, Stop, Run All)
    ;   (gap to LV):  10px
    statusY := height - 30              ; 22px bar + 8px margin
    chk2Y := statusY - 28              ; 22px chk + 6px gap
    chkY := chk2Y - 26                 ; 22px chk + 4px gap
    refreshY := chkY - 34              ; 26px btns + 8px gap
    btn2Y := refreshY - 40             ; 32px btns + 8px gap
    btnY := btn2Y - 42                 ; 32px btns + 10px gap
    lvH := btnY - 70                   ; header ~60px + 10px gap below

    if (lvH < 60)
        lvH := 60

    MainLV.Move(,, lvW, lvH)

    ; Button row
    xPos := mx
    BtnAdd.Move(xPos, btnY)
    xPos += 88
    BtnEdit.Move(xPos, btnY)
    xPos += 88
    BtnDelete.Move(xPos, btnY)
    xPos += 88
    BtnMoveUp.Move(xPos, btnY)
    xPos += 36
    BtnMoveDown.Move(xPos, btnY)
    xPos += 57
    BtnRun.Move(xPos, btnY)
    xPos += 88
    BtnStop.Move(xPos, btnY)
    xPos += 105
    BtnRunAll.Move(xPos, btnY)

    ; Button row 2
    xPos := mx
    BtnClose.Move(xPos, btn2Y)
    xPos += 88
    BtnCloseAll.Move(xPos, btn2Y)
    xPos += 98
    BtnStopAll.Move(xPos, btn2Y)
    xPos += 105
    BtnPause.Move(xPos, btn2Y)
    xPos += 98
    BtnHideToggle.Move(xPos, btn2Y)
    BtnHelp.Move(width - mx - 32, btn2Y)

    ; Refresh row
    xPos := mx
    TxtRefreshLabel.Move(xPos, refreshY + 3)
    xPos += 115
    EdRefreshInterval.Move(xPos, refreshY + 2)
    xPos += 75
    BtnRefreshStart.Move(xPos, refreshY)
    xPos += 105
    BtnRefreshStop.Move(xPos, refreshY)
    xPos += 105
    BtnRefreshDisplay.Move(xPos, refreshY)

    ; Toggle checkboxes row 1
    ChkGlobalAutoStart.Move(mx, chkY)
    ChkAutoRefresh.Move(mx + 250, chkY)

    ; Toggle checkboxes row 2
    ChkAutoShowCountdown.Move(mx, chk2Y)
    ChkAutoHideCountdown.Move(mx + 250, chk2Y)

    ; Status bar
    TxtStatusBar.Move(mx, statusY, lvW)
}

OnMainClose(thisGui) {
    CleanupAndExit()
}

OnMainLVDoubleClick(ctrl, row) {
    if (row > 0)
        OpenSetupEditor(row)
}

; ============================================================================
; Main GUI Button Handlers
; ============================================================================
OnAddSetup(*) {
    OpenSetupEditor(0)
}

OnEditSetup(*) {
    row := MainLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a setup to edit.", APP_NAME, "Icon!")
        return
    }
    OpenSetupEditor(row)
}

OnDeleteSetup(*) {
    row := MainLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a setup to delete.", APP_NAME, "Icon!")
        return
    }

    setup := Setups[row]
    result := MsgBox("Delete setup '" setup.Name "'?`n`nThis cannot be undone.", APP_NAME, "YesNo Icon!")
    if (result = "Yes") {
        LogInfo("Deleting setup #" row ": " setup.Name)
        ; Show hidden window before deleting so it's not stranded off-screen
        ShowSetupWindow(row)
        UnregisterKeepAliveThumb("setup_" row)
        StopSetup(row)
        Setups.RemoveAt(row)
        ; Remap ALL index-keyed global maps to account for shifted indices
        RemapGlobalIndices(row)
        SaveAllSetups()
        RefreshMainLV()
    }
}

OnMoveSetupUp(*) {
    row := MainLV.GetNext(0)
    if (row <= 1)
        return
    LogInfo("Moving setup #" row " (" Setups[row].Name ") up")
    temp := Setups[row - 1]
    Setups[row - 1] := Setups[row]
    Setups[row] := temp
    SwapGlobalIndices(row, row - 1)
    SaveAllSetups()
    RefreshMainLV()
    MainLV.Modify(row - 1, "Select Focus")
}

OnMoveSetupDown(*) {
    row := MainLV.GetNext(0)
    if (row = 0 || row >= Setups.Length)
        return
    LogInfo("Moving setup #" row " (" Setups[row].Name ") down")
    temp := Setups[row + 1]
    Setups[row + 1] := Setups[row]
    Setups[row] := temp
    SwapGlobalIndices(row, row + 1)
    SaveAllSetups()
    RefreshMainLV()
    MainLV.Modify(row + 1, "Select Focus")
}

OnRunSetup(*) {
    row := MainLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a setup to run.", APP_NAME, "Icon!")
        return
    }
    RunSetup(row)
}

OnStopSetup(*) {
    row := MainLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a setup to stop.", APP_NAME, "Icon!")
        return
    }
    StopSetup(row)
    RefreshMainLV()
}

OnRunAllAutoStart(*) {
    SetTimer(RunAutoStartSequential.Bind(false), -100)
}

OnCloseSetup(*) {
    global MonitoredHwnds
    row := MainLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a setup to close.", APP_NAME, "Icon!")
        return
    }
    CloseSetupWindow(row)
    StopSetup(row)
    SetupStatuses[row] := "Closed"
    RefreshMainLV()
}

OnCloseAllSetups(*) {
    global MonitoredHwnds
    ; Collect HWNDs before StopSetup clears them
    hwndsToClose := Map()
    for idx, setup in Setups {
        if MonitoredHwnds.Has(idx)
            hwndsToClose[idx] := MonitoredHwnds[idx]
        ; Show hidden windows first so WinClose can reach them
        ShowSetupWindow(idx)
        StopSetup(idx)
        SetupStatuses[idx] := "Closed"
    }
    ; Now close all collected windows
    for idx, hwnd in hwndsToClose {
        try {
            WinClose("ahk_id " hwnd)
            if WinWaitClose("ahk_id " hwnd,, 2)
                continue
            WinKill("ahk_id " hwnd)
        }
    }
    StopRefreshCycle()
    RefreshMainLV()
}

CloseSetupWindow(idx) {
    global MonitoredHwnds
    if !MonitoredHwnds.Has(idx)
        return
    ShowSetupWindow(idx)
    hwnd := MonitoredHwnds[idx]
    try {
        WinClose("ahk_id " hwnd)
        if !WinWaitClose("ahk_id " hwnd,, 2)
            WinKill("ahk_id " hwnd)
    }
}

OnStopAllSetups(*) {
    for idx, setup in Setups {
        StopSetup(idx)
        SetupStatuses[idx] := "Stopped"
    }
    StopRefreshCycle()
    RefreshMainLV()
}

OnGlobalAutoStartToggle(ctrl, *) {
    global GlobalAutoStart
    GlobalAutoStart := ctrl.Value
    SaveAllSetups()
}

OnTogglePause(*) {
    global Paused, BtnPause
    Paused := !Paused
    BtnPause.Text := Paused ? "Resume All" : "Pause All"
    UpdateStatusBar()
}

OnShowHelp(*) {
    helpText := "
    (
Keyboard Shortcuts
-----------------------------
Ctrl+Shift+P    Pause / Resume all automation
Ctrl+Shift+S    Stop all setups
Ctrl+Shift+Q    Close all setup windows
Ctrl+Shift+Esc  Exit application

GUI Controls
-----------------------------
Add / Edit / Delete     Manage setups
Run / Stop              Start or stop a single setup
Close                   Close a setup's window
Close All               Close all setup windows and stop automation
Stop All                Stop all setups without closing windows
Pause All               Freeze all monitors and refresh cycles
Hide/Show               Toggle selected setup's window visibility
Run Auto-Start          Launch all setups marked as Auto-Start

Toggles
-----------------------------
Run Auto-Start on launch    Auto-run setups when script starts
Auto-start refresh          Start refresh after all setups finish

Refresh
-----------------------------
Start / Stop Refresh    Control the shared refresh timer
Show Display            Toggle floating countdown window
    )"
    MsgBox(helpText, APP_NAME " - Help", "Iconi")
}

; ============================================================================
; Refresh Button Handlers
; ============================================================================
OnStartRefresh(*) {
    global RefreshInterval, EdRefreshInterval
    val := EdRefreshInterval.Value
    if (val = "" || !IsNumber(val) || Integer(val) < 1) {
        MsgBox("Please enter a valid refresh interval (seconds).", APP_NAME, "Icon!")
        return
    }
    RefreshInterval := Integer(val)
    SaveAllSetups()
    StartRefreshCycle()
}

OnStopRefresh(*) {
    StopRefreshCycle()
}

OnToggleDisplay(*) {
    global CountdownVisible, CountdownHidden
    if (CountdownVisible && CountdownHidden)
        RestoreCountdownGui()
    else if (CountdownVisible)
        HideCountdownGui()
    else
        ShowCountdownGui()
}

OnAutoRefreshToggle(ctrl, *) {
    global AutoRefresh
    AutoRefresh := ctrl.Value
    SaveAllSetups()
}

OnAutoShowCountdownToggle(ctrl, *) {
    global AutoShowCountdown
    AutoShowCountdown := ctrl.Value
    SaveAllSetups()
}

OnAutoHideCountdownToggle(ctrl, *) {
    global AutoHideCountdown
    AutoHideCountdown := ctrl.Value
    SaveAllSetups()
}

; ============================================================================
; Setup Editor GUI
; ============================================================================
OpenSetupEditor(editIndex) {
    global EditorGui, EditingIndex, TempSteps, EdStepLV
    global TempRefreshSteps, EdRefreshStepLV, EditorOpen
    EditorOpen := true
    try BlockInput("Default")
    try BlockInput("MouseMoveOff")  ; Clear any stuck BlockInput
    EditingIndex := editIndex

    if (editIndex > 0) {
        setup := Setups[editIndex]
        TempSteps := []
        for _, step in setup.Steps {
            s := StepData()
            s.Key := step.Key
            s.Mode := step.Mode
            s.Value := step.Value
            TempSteps.Push(s)
        }
        TempRefreshSteps := []
        for _, step in setup.RefreshSteps {
            s := StepData()
            s.Key := step.Key
            s.Mode := step.Mode
            s.Value := step.Value
            TempRefreshSteps.Push(s)
        }
    } else {
        TempSteps := []
        TempRefreshSteps := []
    }

    EditorGui := Gui("+Owner" MainGui.Hwnd " -MinimizeBox", (editIndex > 0 ? "Edit" : "Add") " Setup")
    EditorGui.SetFont("s10", "Segoe UI")
    EditorGui.BackColor := "FFFFFF"
    EditorGui.MarginX := 10
    EditorGui.MarginY := 8

    ; Tab control
    edTab := EditorGui.AddTab3("xm ym w480 h440", ["General", "Nav Steps", "Refresh Steps"])

    ; ===================== Tab 1: General =====================
    edTab.UseTab("General")

    EditorGui.SetFont("s10 Norm", "Segoe UI")
    EditorGui.AddText("xm+15 ym+40 w90", "Name:")
    EditorGui.AddEdit("x+5 yp-3 w355 vEdName", editIndex > 0 ? setup.Name : "")

    EditorGui.AddText("xm+15 y+10 w90", "Shortcut (.lnk):")
    EditorGui.AddEdit("x+5 yp-3 w270 vEdPath", editIndex > 0 ? setup.ShortcutPath : "")
    btnBrowse := EditorGui.AddButton("x+5 yp w75 h24", "Browse...")
    btnBrowse.OnEvent("Click", OnBrowseShortcut)

    EditorGui.AddText("xm+15 y+10 w90", "Window Title:")
    EditorGui.AddEdit("x+5 yp-3 w270 vEdTitle", editIndex > 0 ? setup.WindowTitle : "")
    btnDetect := EditorGui.AddButton("x+5 yp w75 h24", "Detect")
    btnDetect.OnEvent("Click", OnDetectTitle)

    ; -- Options --
    EditorGui.AddText("xm+15 y+14 w450 h1 BackgroundDDDDDD")

    chkAuto := EditorGui.AddCheckbox("xm+15 y+10 w220 vChkAutoStart", "Auto-Start on script launch")
    if (editIndex > 0 && setup.AutoStart)
        chkAuto.Value := 1
    chkHide := EditorGui.AddCheckbox("x+10 yp w220 vChkHideWindow", "Hide window after launch")
    if (editIndex > 0 && setup.HideWindow)
        chkHide.Value := 1

    chkKeep := EditorGui.AddCheckbox("xm+15 y+8 w220 vChkKeepActive", "Keep Active (relaunch if closed)")
    if (editIndex > 0 && setup.KeepActive)
        chkKeep.Value := 1
    chkKeep.OnEvent("Click", OnKeepActiveToggle)
    EditorGui.AddText("x+10 yp+2 w100", "Check interval (ms):")
    edInterval := EditorGui.AddEdit("x+5 yp-3 w65 vEdInterval Number", editIndex > 0 ? String(setup.CheckInterval) : "5000")
    if (editIndex = 0 || !setup.KeepActive)
        edInterval.Enabled := false

    EditorGui.AddText("xm+15 y+8 w140", "Auto-Close Window (Title):")
    EditorGui.AddEdit("x+5 yp-3 w305 vEdCloseBatchTitle", editIndex > 0 ? setup.CloseBatchTitle : "")

    ; -- Network Check --
    EditorGui.AddText("xm+15 y+14 w450 h1 BackgroundDDDDDD")

    chkNet := EditorGui.AddCheckbox("xm+15 y+10 vChkCheckNet", "Wait for network before launching")
    if (editIndex > 0 && setup.CheckNet)
        chkNet.Value := 1
    chkNet.OnEvent("Click", OnCheckNetToggle)

    EditorGui.AddText("xm+15 y+8 w50", "Address:")
    edNetAddr := EditorGui.AddEdit("x+5 yp-3 w140 vEdNetAddress", editIndex > 0 ? setup.NetAddress : "")
    EditorGui.AddText("x+10 yp+3 w30", "Port:")
    edNetPort := EditorGui.AddEdit("x+5 yp-3 w55 vEdNetPort Number", editIndex > 0 ? setup.NetPort : "")
    EditorGui.AddText("x+10 yp+3 w50", "Timeout:")
    edNetTimeout := EditorGui.AddEdit("x+5 yp-3 w40 vEdNetTimeout Number", editIndex > 0 ? String(setup.NetTimeout) : "30")
    EditorGui.AddText("x+2 yp+3", "s")

    EditorGui.AddText("xm+15 y+8 w70", "Retry delay:")
    edNetRetry := EditorGui.AddEdit("x+5 yp-3 w40 vEdNetRetryDelay Number", editIndex > 0 ? String(setup.NetRetryDelay) : "5")
    EditorGui.AddText("x+2 yp+3", "s (after timeout)")

    if (editIndex = 0 || !setup.CheckNet) {
        edNetAddr.Enabled := false
        edNetPort.Enabled := false
        edNetTimeout.Enabled := false
        edNetRetry.Enabled := false
    }

    ; ===================== Tab 2: Navigation Steps =====================
    edTab.UseTab("Nav Steps")

    EditorGui.SetFont("s10 Norm", "Segoe UI")
    EditorGui.AddText("xm+15 ym+40 w450 cGray", "Keys sent after the application opens")

    EdStepLV := EditorGui.AddListView("xm+15 y+8 w450 h280 Grid NoSortHdr", ["#", "Key", "Mode", "Value"])
    EdStepLV.ModifyCol(1, 30)
    EdStepLV.ModifyCol(2, 140)
    EdStepLV.ModifyCol(3, 100)
    EdStepLV.ModifyCol(4, 170)

    btnAddStep := EditorGui.AddButton("xm+15 y+6 w80 h26", "Add Step")
    btnAddStep.OnEvent("Click", OnAddNavStep)
    btnEditStep := EditorGui.AddButton("x+5 yp w80 h26", "Edit Step")
    btnEditStep.OnEvent("Click", OnEditNavStep)
    btnDelStep := EditorGui.AddButton("x+5 yp w80 h26", "Delete Step")
    btnDelStep.OnEvent("Click", OnDeleteNavStep)
    btnUp := EditorGui.AddButton("x+15 yp w35 h26", Chr(9650))
    btnUp.OnEvent("Click", OnMoveNavStepUp)
    btnDown := EditorGui.AddButton("x+5 yp w35 h26", Chr(9660))
    btnDown.OnEvent("Click", OnMoveNavStepDown)

    ; ===================== Tab 3: Refresh Steps =====================
    edTab.UseTab("Refresh Steps")

    EditorGui.SetFont("s10 Norm", "Segoe UI")
    EditorGui.AddText("xm+15 ym+40 w450 cGray", "Keys sent on each refresh cycle (shared timer)")

    EdRefreshStepLV := EditorGui.AddListView("xm+15 y+8 w450 h280 Grid NoSortHdr", ["#", "Key", "Mode", "Value"])
    EdRefreshStepLV.ModifyCol(1, 30)
    EdRefreshStepLV.ModifyCol(2, 140)
    EdRefreshStepLV.ModifyCol(3, 100)
    EdRefreshStepLV.ModifyCol(4, 170)

    btnAddRStep := EditorGui.AddButton("xm+15 y+6 w80 h26", "Add Step")
    btnAddRStep.OnEvent("Click", OnAddRefreshStep)
    btnEditRStep := EditorGui.AddButton("x+5 yp w80 h26", "Edit Step")
    btnEditRStep.OnEvent("Click", OnEditRefreshStep)
    btnDelRStep := EditorGui.AddButton("x+5 yp w80 h26", "Delete Step")
    btnDelRStep.OnEvent("Click", OnDeleteRefreshStep)
    btnRUp := EditorGui.AddButton("x+15 yp w35 h26", Chr(9650))
    btnRUp.OnEvent("Click", OnMoveRefreshStepUp)
    btnRDown := EditorGui.AddButton("x+5 yp w35 h26", Chr(9660))
    btnRDown.OnEvent("Click", OnMoveRefreshStepDown)

    ; ===================== Outside tabs: Save / Cancel =====================
    edTab.UseTab()

    ; Position buttons absolutely below the tab control (tab is ym=8, h440, so bottom = 448)
    btnSave := EditorGui.AddButton("xm y458 w100 h32 Default", "Save")
    btnSave.OnEvent("Click", OnSaveSetup)
    btnCancel := EditorGui.AddButton("x+10 yp w100 h32", "Cancel")
    btnCancel.OnEvent("Click", OnCancelEditor)

    EditorGui.OnEvent("Close", OnCancelEditor)

    RefreshEditorNavStepLV()
    RefreshEditorRefreshStepLV()
    EditorGui.Show("w500 h500")
}

RefreshEditorNavStepLV() {
    global EdStepLV, TempSteps
    EdStepLV.Delete()
    for idx, step in TempSteps {
        modeLabel := (step.Mode = "delay") ? "Delay (ms)" : "Wait Window"
        EdStepLV.Add("", idx, step.Key, modeLabel, step.Value)
    }
}

RefreshEditorRefreshStepLV() {
    global EdRefreshStepLV, TempRefreshSteps
    EdRefreshStepLV.Delete()
    for idx, step in TempRefreshSteps {
        modeLabel := (step.Mode = "delay") ? "Delay (ms)" : "Wait Window"
        EdRefreshStepLV.Add("", idx, step.Key, modeLabel, step.Value)
    }
}

OnBrowseShortcut(ctrl, *) {
    selectedFile := FileSelect(1,, "Select Shortcut", "Shortcuts (*.lnk)")
    if (selectedFile != "")
        EditorGui["EdPath"].Value := selectedFile
}

OnDetectTitle(ctrl, *) {
    path := EditorGui["EdPath"].Value
    if (path = "") {
        MsgBox("Please set a shortcut path first.", APP_NAME, "Icon!")
        return
    }
    if !FileExist(path) {
        MsgBox("Shortcut file not found:`n" path, APP_NAME, "IconX")
        return
    }

    MsgBox("The shortcut will now launch.`nAfter the application window appears, click OK in the next dialog to capture its title.", APP_NAME, "Icon!")

    try {
        Run(path)
        Sleep(3000)
        MsgBox("Click OK when the application window is in the foreground.", APP_NAME, "Icon!")
        title := WinGetTitle("A")
        if (title != "" && title != APP_NAME && title != "Edit Setup" && title != "Add Setup") {
            EditorGui["EdTitle"].Value := title
            MsgBox("Detected title: " title, APP_NAME, "Iconi")
        } else {
            MsgBox("Could not detect a valid window title. Please type it manually.", APP_NAME, "Icon!")
        }
    } catch as e {
        MsgBox("Error launching shortcut: " e.Message, APP_NAME, "IconX")
    }
}

OnKeepActiveToggle(ctrl, *) {
    EditorGui["EdInterval"].Enabled := ctrl.Value
}

OnCheckNetToggle(ctrl, *) {
    enabled := ctrl.Value
    EditorGui["EdNetAddress"].Enabled := enabled
    EditorGui["EdNetPort"].Enabled := enabled
    EditorGui["EdNetTimeout"].Enabled := enabled
    EditorGui["EdNetRetryDelay"].Enabled := enabled
}

OnSaveSetup(ctrl, *) {
    global EditingIndex, TempSteps, TempRefreshSteps, EditorGui, Setups, SetupStatuses

    name := EditorGui["EdName"].Value
    path := EditorGui["EdPath"].Value
    title := EditorGui["EdTitle"].Value

    if (name = "") {
        MsgBox("Please enter a name.", APP_NAME, "Icon!")
        return
    }
    if (path = "") {
        MsgBox("Please select a shortcut.", APP_NAME, "Icon!")
        return
    }

    setup := SetupData()
    setup.Name := name
    setup.ShortcutPath := path
    setup.WindowTitle := title
    setup.AutoStart := EditorGui["ChkAutoStart"].Value
    setup.KeepActive := EditorGui["ChkKeepActive"].Value
    interval := EditorGui["EdInterval"].Value
    setup.CheckInterval := (interval != "" && IsNumber(interval) && Integer(interval) > 0) ? Integer(interval) : 5000
    setup.CheckNet := EditorGui["ChkCheckNet"].Value
    setup.NetAddress := EditorGui["EdNetAddress"].Value
    setup.NetPort := EditorGui["EdNetPort"].Value
    netTimeout := EditorGui["EdNetTimeout"].Value
    setup.NetTimeout := (netTimeout != "" && IsNumber(netTimeout) && Integer(netTimeout) > 0) ? Integer(netTimeout) : 30
    netRetry := EditorGui["EdNetRetryDelay"].Value
    setup.NetRetryDelay := (netRetry != "" && IsNumber(netRetry) && Integer(netRetry) > 0) ? Integer(netRetry) : 5
    setup.HideWindow := EditorGui["ChkHideWindow"].Value
    setup.CloseBatchTitle := EditorGui["EdCloseBatchTitle"].Value
    setup.Steps := TempSteps
    setup.RefreshSteps := TempRefreshSteps

    ; Preserve LastTitle from existing setup (auto-captured, not user-editable)
    if (EditingIndex > 0 && Setups[EditingIndex].LastTitle != "")
        setup.LastTitle := Setups[EditingIndex].LastTitle

    if (EditingIndex > 0) {
        LogInfo("Updating setup #" EditingIndex ": " setup.Name)
        Setups[EditingIndex] := setup
    } else {
        LogInfo("Adding new setup: " setup.Name)
        Setups.Push(setup)
        SetupStatuses[Setups.Length] := "Stopped"
    }

    SaveAllSetups()
    RefreshMainLV()
    EditorOpen := false
    EditorGui.Destroy()
}

OnCancelEditor(*) {
    global EditorOpen
    EditorOpen := false
    EditorGui.Destroy()
}

; ============================================================================
; Navigation Step Handlers
; ============================================================================
OnAddNavStep(*) {
    global EditingRefreshStep
    EditingRefreshStep := false
    OpenStepEditor(0)
}

OnEditNavStep(*) {
    global EdStepLV, EditingRefreshStep
    row := EdStepLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a step to edit.", APP_NAME, "Icon!")
        return
    }
    EditingRefreshStep := false
    OpenStepEditor(row)
}

OnDeleteNavStep(*) {
    global EdStepLV, TempSteps
    row := EdStepLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a step to delete.", APP_NAME, "Icon!")
        return
    }
    TempSteps.RemoveAt(row)
    RefreshEditorNavStepLV()
}

OnMoveNavStepUp(*) {
    global EdStepLV, TempSteps
    row := EdStepLV.GetNext(0)
    if (row <= 1)
        return
    temp := TempSteps[row - 1]
    TempSteps[row - 1] := TempSteps[row]
    TempSteps[row] := temp
    RefreshEditorNavStepLV()
    EdStepLV.Modify(row - 1, "Select Focus")
}

OnMoveNavStepDown(*) {
    global EdStepLV, TempSteps
    row := EdStepLV.GetNext(0)
    if (row = 0 || row >= TempSteps.Length)
        return
    temp := TempSteps[row + 1]
    TempSteps[row + 1] := TempSteps[row]
    TempSteps[row] := temp
    RefreshEditorNavStepLV()
    EdStepLV.Modify(row + 1, "Select Focus")
}

; ============================================================================
; Refresh Step Handlers
; ============================================================================
OnAddRefreshStep(*) {
    global EditingRefreshStep
    EditingRefreshStep := true
    OpenStepEditor(0)
}

OnEditRefreshStep(*) {
    global EdRefreshStepLV, EditingRefreshStep
    row := EdRefreshStepLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a step to edit.", APP_NAME, "Icon!")
        return
    }
    EditingRefreshStep := true
    OpenStepEditor(row)
}

OnDeleteRefreshStep(*) {
    global EdRefreshStepLV, TempRefreshSteps
    row := EdRefreshStepLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a step to delete.", APP_NAME, "Icon!")
        return
    }
    TempRefreshSteps.RemoveAt(row)
    RefreshEditorRefreshStepLV()
}

OnMoveRefreshStepUp(*) {
    global EdRefreshStepLV, TempRefreshSteps
    row := EdRefreshStepLV.GetNext(0)
    if (row <= 1)
        return
    temp := TempRefreshSteps[row - 1]
    TempRefreshSteps[row - 1] := TempRefreshSteps[row]
    TempRefreshSteps[row] := temp
    RefreshEditorRefreshStepLV()
    EdRefreshStepLV.Modify(row - 1, "Select Focus")
}

OnMoveRefreshStepDown(*) {
    global EdRefreshStepLV, TempRefreshSteps
    row := EdRefreshStepLV.GetNext(0)
    if (row = 0 || row >= TempRefreshSteps.Length)
        return
    temp := TempRefreshSteps[row + 1]
    TempRefreshSteps[row + 1] := TempRefreshSteps[row]
    TempRefreshSteps[row] := temp
    RefreshEditorRefreshStepLV()
    EdRefreshStepLV.Modify(row + 1, "Select Focus")
}

; ============================================================================
; Step Editor GUI (shared by nav and refresh steps)
; ============================================================================
OpenStepEditor(stepIndex) {
    global StepEditorGui, EditingStepIndex, EditingRefreshStep
    global TempSteps, TempRefreshSteps
    EditingStepIndex := stepIndex

    ; Pick the right step list based on which section we're editing
    activeSteps := EditingRefreshStep ? TempRefreshSteps : TempSteps
    titlePrefix := EditingRefreshStep ? "Refresh " : "Navigation "

    StepEditorGui := Gui("+Owner" EditorGui.Hwnd " -MinimizeBox", (stepIndex > 0 ? "Edit " : "Add ") titlePrefix "Step")
    StepEditorGui.SetFont("s10", "Segoe UI")
    StepEditorGui.BackColor := "FFFFFF"

    StepEditorGui.SetFont("s11 Bold", "Segoe UI")
    StepEditorGui.AddText("xm ym w350", titlePrefix "Step")
    StepEditorGui.SetFont("s10 Norm", "Segoe UI")

    StepEditorGui.AddText("xm y+12 w120", "Key / Combo:")
    StepEditorGui.AddEdit("x+5 yp-3 w220 vStKey", stepIndex > 0 ? activeSteps[stepIndex].Key : "")
    StepEditorGui.SetFont("s9", "Segoe UI")
    StepEditorGui.AddText("xm y+3 w350 cGray", "AHK syntax: {F1}-{F12}, {Enter}, {Tab}, !x=Alt+X, ^x=Ctrl+X, +x=Shift+X")
    StepEditorGui.SetFont("s10 Norm", "Segoe UI")

    StepEditorGui.AddText("xm y+12 w120", "Mode:")
    modeChoice := (stepIndex > 0 && activeSteps[stepIndex].Mode = "window") ? 2 : 1
    ddl := StepEditorGui.AddDropDownList("x+5 yp-3 w220 vStMode Choose" modeChoice, ["Delay (ms)", "Wait for Window Title"])
    ddl.OnEvent("Change", OnStepModeChange)

    StepEditorGui.AddText("xm y+12 w120 vStValLabel", modeChoice = 1 ? "Delay (ms):" : "Window Title:")
    StepEditorGui.AddEdit("x+5 yp-3 w220 vStValue", stepIndex > 0 ? activeSteps[stepIndex].Value : "500")

    StepEditorGui.AddText("xm y+20 w350 h1 BackgroundDDDDDD")

    btnSaveStep := StepEditorGui.AddButton("xm y+10 w100 h30 Default", "Save")
    btnSaveStep.OnEvent("Click", OnSaveStep)

    btnCancelStep := StepEditorGui.AddButton("x+10 yp w100 h30", "Cancel")
    btnCancelStep.OnEvent("Click", OnCancelStep)

    StepEditorGui.OnEvent("Close", OnCancelStep)
    StepEditorGui.Show()
}

OnStepModeChange(ctrl, *) {
    if (ctrl.Value = 1)
        StepEditorGui["StValLabel"].Value := "Delay (ms):"
    else
        StepEditorGui["StValLabel"].Value := "Window Title:"
}

OnSaveStep(ctrl, *) {
    global EditingStepIndex, EditingRefreshStep
    global TempSteps, TempRefreshSteps

    key := StepEditorGui["StKey"].Value
    modeIdx := StepEditorGui["StMode"].Value
    value := StepEditorGui["StValue"].Value

    if (key = "") {
        MsgBox("Please enter a key or combo.", APP_NAME, "Icon!")
        return
    }
    if (value = "") {
        MsgBox("Please enter a value.", APP_NAME, "Icon!")
        return
    }

    step := StepData()
    step.Key := key
    step.Mode := (modeIdx = 1) ? "delay" : "window"
    step.Value := value

    if (EditingRefreshStep) {
        if (EditingStepIndex > 0)
            TempRefreshSteps[EditingStepIndex] := step
        else
            TempRefreshSteps.Push(step)
        RefreshEditorRefreshStepLV()
    } else {
        if (EditingStepIndex > 0)
            TempSteps[EditingStepIndex] := step
        else
            TempSteps.Push(step)
        RefreshEditorNavStepLV()
    }

    StepEditorGui.Destroy()
}

OnCancelStep(*) {
    StepEditorGui.Destroy()
}

; ============================================================================
; Network Availability Check
; ============================================================================
IsPortOpen(host, port, timeout := 1000) {
    wsaData := Buffer(400, 0)
    DllCall("Ws2_32\WSAStartup", "UShort", 0x202, "Ptr", wsaData)

    sock := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if (sock = -1) {
        DllCall("Ws2_32\WSACleanup")
        return false
    }

    ; Set non-blocking mode
    mode := 1
    DllCall("Ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "UInt*", &mode)

    ; Build sockaddr_in structure
    sockAddr := Buffer(16, 0)
    NumPut("Short", 2, sockAddr, 0)  ; AF_INET
    NumPut("UShort", DllCall("Ws2_32\htons", "UShort", port, "UShort"), sockAddr, 2)
    NumPut("UInt", DllCall("Ws2_32\inet_addr", "AStr", host, "UInt"), sockAddr, 4)

    ; Attempt connect
    DllCall("Ws2_32\connect", "Ptr", sock, "Ptr", sockAddr, "Int", 16)

    ; Use select() to wait for connection
    ; fd_set struct: u_int fd_count then SOCKET fd_array[]
    ; On 64-bit, SOCKET (8 bytes) needs 8-byte alignment → 4 bytes padding after fd_count
    writeFds := Buffer(A_PtrSize + A_PtrSize, 0)
    NumPut("UInt", 1, writeFds, 0)
    NumPut("Ptr", sock, writeFds, A_PtrSize)

    timeVal := Buffer(8, 0)
    NumPut("Int", timeout // 1000, timeVal, 0)
    NumPut("Int", Mod(timeout, 1000) * 1000, timeVal, 4)

    result := DllCall("Ws2_32\select", "Int", 0, "Ptr", 0, "Ptr", writeFds, "Ptr", 0, "Ptr", timeVal)

    DllCall("Ws2_32\closesocket", "Ptr", sock)
    DllCall("Ws2_32\WSACleanup")

    return (result > 0)
}

CheckNetworkAvailable(address, port, timeoutSec) {
    deadline := A_TickCount + (timeoutSec * 1000)
    portNum := Integer(port)
    Loop {
        if (A_TickCount > deadline)
            return false
        if IsPortOpen(address, portNum, 2000)
            return true
        Sleep(3000)
    }
    return false
}

; ============================================================================
; Core Execution Logic
; ============================================================================
RunSetup(idx) {
    global Setups, SetupStatuses, MonitorTimers, MonitoredTitles, MonitoredHwnds, SetupRunning

    if (idx < 1 || idx > Setups.Length)
        return

    ; Flag to prevent timer callbacks from interfering (checked by MonitorCallback, ExecuteRefreshCycle)
    SetupRunning := true

    setup := Setups[idx]

    if (setup.ShortcutPath = "" || !FileExist(setup.ShortcutPath)) {
        SetupRunning := false
        LogError("Shortcut not found for '" setup.Name "': " setup.ShortcutPath)
        MsgBox("Shortcut not found for '" setup.Name "':`n" setup.ShortcutPath, APP_NAME, "IconX")
        return
    }

    ; Check if a matching window already exists — adopt it instead of relaunching
    ; Try LastTitle first (the final title after navigation), then fall back to WindowTitle
    claimedHwnds := Map()
    for otherIdx, otherHwnd in MonitoredHwnds
        claimedHwnds[otherHwnd] := true

    titlesToTry := []
    if (setup.LastTitle != "")
        titlesToTry.Push(setup.LastTitle)
    if (setup.WindowTitle != "" && setup.WindowTitle != setup.LastTitle)
        titlesToTry.Push(setup.WindowTitle)

    for _, searchTitle in titlesToTry {
        try {
            for candidateHwnd in WinGetList(searchTitle) {
                if !claimedHwnds.Has(candidateHwnd) {
                    MonitoredHwnds[idx] := candidateHwnd
                    MonitoredTitles[idx] := WinGetTitle("ahk_id " candidateHwnd)
                    if (setup.KeepActive || setup.CloseBatchTitle != "") {
                        SetupStatuses[idx] := (setup.KeepActive) ? "Monitoring" : "Running"
                        StartMonitor(idx)
                    } else {
                        SetupStatuses[idx] := "Running"
                    }
                    if (setup.HideWindow)
                        HideSetupWindow(idx)
                    RefreshMainLV()
                    SetupRunning := false
                    CheckAutoRefreshReady()
                    return
                }
            }
        }
    }

    ; Network availability check with retry
    if (setup.CheckNet && setup.NetAddress != "" && setup.NetPort != "") {
        LogInfo("Waiting for network: " setup.NetAddress ":" setup.NetPort " (timeout " setup.NetTimeout "s)")
        SetupStatuses[idx] := "Waiting for network..."
        RefreshMainLV()
        available := CheckNetworkAvailable(setup.NetAddress, setup.NetPort, setup.NetTimeout)
        if (!available) {
            retryDelay := setup.NetRetryDelay > 0 ? setup.NetRetryDelay : 5
            LogInfo("Network unavailable for '" setup.Name "', retrying in " retryDelay "s")
            SetupStatuses[idx] := "Net retry in " retryDelay "s..."
            RefreshMainLV()
            Sleep(retryDelay * 1000)
            RunSetup(idx)
            return
        }
    }

    LogInfo("Launching setup #" idx ": " setup.Name)
    SetupStatuses[idx] := "Launching..."
    RefreshMainLV()

    ; Snapshot existing windows with this title BEFORE launching
    existingHwnds := Map()
    if (setup.WindowTitle != "") {
        try {
            for existHwnd in WinGetList(setup.WindowTitle)
                existingHwnds[existHwnd] := true
        }
    }

    ; Snapshot existing BATCH windows BEFORE launching
    existingBatchHwnds := Map()
    if (setup.CloseBatchTitle != "") {
        try {
            for bHwnd in WinGetList(setup.CloseBatchTitle)
                existingBatchHwnds[bHwnd] := true
        }
    }

    ; Launch the shortcut
    try {
        Run(setup.ShortcutPath)
    } catch as e {
        LogError("Failed to launch '" setup.Name "': " e.Message)
        SetupStatuses[idx] := "Error"
        RefreshMainLV()
        SetupRunning := false
        MsgBox("Failed to launch '" setup.Name "':`n" e.Message, APP_NAME, "IconX")
        return
    }

    ; Try to identify the NEW batch window launched by this shortcut
    batchHwnd := 0
    if (setup.CloseBatchTitle != "") {
        timeoutBatch := A_TickCount + 5000
        Loop {
            if (A_TickCount > timeoutBatch)
                break
            Sleep(100)
            try {
                for bHwnd in WinGetList(setup.CloseBatchTitle) {
                    if !existingBatchHwnds.Has(bHwnd) {
                        batchHwnd := bHwnd
                        break 2
                    }
                }
            }
        }
    }

    ; Wait for a NEW window (one that wasn't in the snapshot)
    hwnd := 0
    if (setup.WindowTitle != "") {
        timeout := A_TickCount + 30000
        Loop {
            if (A_TickCount > timeout) {
                ; Failure: Close the batch window we just opened
                if (batchHwnd) {
                    LogInfo("Closing failed attempt's batch window for '" setup.Name "': ahk_id " batchHwnd)
                    try {
                        WinClose("ahk_id " batchHwnd)
                        if !WinWaitClose("ahk_id " batchHwnd,, 2)
                            WinKill("ahk_id " batchHwnd)
                    }
                }

                ; Close any partially opened window and retry silently
                try {
                    for candidateHwnd in WinGetList(setup.WindowTitle) {
                        if !existingHwnds.Has(candidateHwnd) {
                            WinClose("ahk_id " candidateHwnd)
                            if !WinWaitClose("ahk_id " candidateHwnd,, 2)
                                WinKill("ahk_id " candidateHwnd)
                        }
                    }
                }
                SetupStatuses[idx] := "Retrying..."
                RefreshMainLV()
                Sleep(1000)
                RunSetup(idx)
                return
            }
            Sleep(200)
            try {
                for candidateHwnd in WinGetList(setup.WindowTitle) {
                    if !existingHwnds.Has(candidateHwnd) {
                        hwnd := candidateHwnd
                        break 2
                    }
                }
            }
        }
        Sleep(500)
        try WinActivate("ahk_id " hwnd)
        Sleep(300)
    } else {
        Sleep(2000)
        try hwnd := WinGetID("A")
    }

    ; Store the initial HWND
    if (hwnd)
        MonitoredHwnds[idx] := hwnd

    ; Block physical input during navigation to prevent interference
    try BlockInput("SendAndMouse")
    try BlockInput("MouseMove")

    ; Execute navigation steps — send keys directly to HWND via ControlSend
    try {
        for _, step in setup.Steps {
            if (step.Mode = "delay") {
                delay := IsNumber(step.Value) ? Integer(step.Value) : 500
                Sleep(delay)
            } else if (step.Mode = "window") {
                if !WinWait(step.Value,, 15) {
                    ; Failure in navigation steps: Close our specific batch window
                    if (batchHwnd) {
                        LogInfo("Closing batch window after nav failure for '" setup.Name "': ahk_id " batchHwnd)
                        try {
                            WinClose("ahk_id " batchHwnd)
                            if !WinWaitClose("ahk_id " batchHwnd,, 2)
                                WinKill("ahk_id " batchHwnd)
                        }
                    }

                    ; Close the window and retry silently
                    try BlockInput("Default")
    try BlockInput("MouseMoveOff")
                    if (hwnd) {
                        try WinClose("ahk_id " hwnd)
                        try {
                            if !WinWaitClose("ahk_id " hwnd,, 2)
                                WinKill("ahk_id " hwnd)
                        }
                    }
                    SetupStatuses[idx] := "Retrying..."
                    RefreshMainLV()
                    Sleep(1000)
                    RunSetup(idx)
                    return
                }
                ; Update hwnd if a window-wait step changed the target
                try {
                    WinActivate(step.Value)
                    Sleep(200)
                    hwnd := WinGetID(step.Value)
                    MonitoredHwnds[idx] := hwnd
                }
            }

            ; Send keys via SendEvent with key delay (reliable for modifier combos
            ; across scripts — each key goes through keybd_event individually)
            try {
                WinActivate("ahk_id " hwnd)
                Sleep(100)
                prevDelay := A_KeyDelay
                prevDuration := A_KeyDuration
                SetKeyDelay(30, 30)
                SendEvent("{Ctrl up}{Shift up}{Alt up}")
                Sleep(30)
                SendEvent(step.Key)
                SetKeyDelay(prevDelay, prevDuration)
            } catch {
                try {
                    ControlSend(step.Key,, "ahk_id " hwnd)
                } catch as e2 {
                    try BlockInput("Default")
    try BlockInput("MouseMoveOff")
                    SetupStatuses[idx] := "Error"
                    RefreshMainLV()
                    SetupRunning := false
                    return
                }
            }
            Sleep(100)
        }
    } finally {
        try BlockInput("Default")
    try BlockInput("MouseMoveOff")
    }

    ; Capture the FINAL window HWND and title after navigation
    Sleep(500)
    try {
        ; Get title directly from the tracked hwnd (not active window which could be wrong)
        WinActivate("ahk_id " hwnd)
        Sleep(200)
        finalHwnd := hwnd
        finalTitle := WinGetTitle("ahk_id " hwnd)
        if (finalHwnd && finalTitle != APP_NAME) {
            MonitoredHwnds[idx] := finalHwnd
            MonitoredTitles[idx] := finalTitle
        } else {
            MonitoredTitles[idx] := setup.WindowTitle
        }
    } catch {
        MonitoredTitles[idx] := setup.WindowTitle
    }

    ; Persist the final title so restart can find this window
    setup.LastTitle := MonitoredTitles[idx]
    SaveAllSetups()

    ; Update status
    if (setup.KeepActive || setup.CloseBatchTitle != "") {
        SetupStatuses[idx] := (setup.KeepActive) ? "Monitoring" : "Running"
        StartMonitor(idx)
    } else {
        SetupStatuses[idx] := "Running"
    }

    ; Auto-hide if option is set
    if (setup.HideWindow)
        HideSetupWindow(idx)

    RefreshMainLV()

    SetupRunning := false

    ; Check if all setups are done and auto-refresh should start
    CheckAutoRefreshReady()
}

StopSetup(idx) {
    global SetupStatuses, MonitorTimers, MonitoredTitles, MonitoredHwnds
    global HiddenPositions, SetupHidden

    LogInfo("Stopping setup #" idx (idx <= Setups.Length ? " (" Setups[idx].Name ")" : ""))

    if MonitorTimers.Has(idx) {
        SetTimer(MonitorTimers[idx], 0)
        MonitorTimers.Delete(idx)
    }

    if MonitoredTitles.Has(idx)
        MonitoredTitles.Delete(idx)
    if HiddenPositions.Has(idx)
        HiddenPositions.Delete(idx)
    if SetupHidden.Has(idx)
        SetupHidden.Delete(idx)
    if MonitoredHwnds.Has(idx)
        MonitoredHwnds.Delete(idx)

    SetupStatuses[idx] := "Stopped"
}

; After Setups.RemoveAt(row), all index-keyed maps have stale keys for indices > row.
; This function rebuilds every map so keys match the new Setups array positions.
RemapGlobalIndices(removedRow) {
    global SetupStatuses, MonitorTimers, MonitoredTitles, MonitoredHwnds
    global HiddenPositions, SetupHidden, DwmKeepAliveThumbs, Setups

    RemapIndexMap(&SetupStatuses, removedRow, Setups.Length, "Stopped")

    ; MonitorTimers needs special handling: stop old timers and re-bind with new indices
    newTimers := Map()
    for idx, s in Setups {
        oldIdx := (idx >= removedRow) ? idx + 1 : idx
        if MonitorTimers.Has(oldIdx) {
            SetTimer(MonitorTimers[oldIdx], 0)
            MonitorTimers.Delete(oldIdx)
            ; Re-create timer bound to the correct new index
            monitorFn := MonitorCallback.Bind(idx)
            newTimers[idx] := monitorFn
            SetTimer(monitorFn, s.CheckInterval > 0 ? s.CheckInterval : 5000)
        }
    }
    MonitorTimers := newTimers

    RemapIndexMap(&MonitoredTitles, removedRow, Setups.Length)
    RemapIndexMap(&MonitoredHwnds, removedRow, Setups.Length)
    RemapIndexMap(&HiddenPositions, removedRow, Setups.Length)
    RemapIndexMap(&SetupHidden, removedRow, Setups.Length)

    ; DwmKeepAliveThumbs uses string keys like "setup_1", remap those too
    newThumbs := Map()
    for idx, s in Setups {
        oldIdx := (idx >= removedRow) ? idx + 1 : idx
        oldKey := "setup_" oldIdx
        newKey := "setup_" idx
        if DwmKeepAliveThumbs.Has(oldKey)
            newThumbs[newKey] := DwmKeepAliveThumbs[oldKey]
    }
    DwmKeepAliveThumbs := newThumbs
}

; Generic helper: rebuild an index-keyed Map after an element was removed at removedRow.
RemapIndexMap(&theMap, removedRow, newLength, defaultVal := "") {
    newMap := Map()
    Loop newLength {
        idx := A_Index
        oldIdx := (idx >= removedRow) ? idx + 1 : idx
        if theMap.Has(oldIdx)
            newMap[idx] := theMap[oldIdx]
        else if (defaultVal != "")
            newMap[idx] := defaultVal
    }
    theMap := newMap
}

; Swap all index-keyed global map entries for two indices (used by move up/down).
SwapGlobalIndices(idxA, idxB) {
    global SetupStatuses, MonitorTimers, MonitoredTitles, MonitoredHwnds
    global HiddenPositions, SetupHidden, DwmKeepAliveThumbs, Setups

    SwapMapEntries(&SetupStatuses, idxA, idxB)
    SwapMapEntries(&MonitoredTitles, idxA, idxB)
    SwapMapEntries(&MonitoredHwnds, idxA, idxB)
    SwapMapEntries(&HiddenPositions, idxA, idxB)
    SwapMapEntries(&SetupHidden, idxA, idxB)

    ; MonitorTimers: stop old timers, rebind with swapped indices, restart
    hasA := MonitorTimers.Has(idxA), hasB := MonitorTimers.Has(idxB)
    if (hasA) {
        SetTimer(MonitorTimers[idxA], 0)
        MonitorTimers.Delete(idxA)
    }
    if (hasB) {
        SetTimer(MonitorTimers[idxB], 0)
        MonitorTimers.Delete(idxB)
    }
    if (hasA) {
        fn := MonitorCallback.Bind(idxB)
        MonitorTimers[idxB] := fn
        SetTimer(fn, Setups[idxB].CheckInterval > 0 ? Setups[idxB].CheckInterval : 5000)
    }
    if (hasB) {
        fn := MonitorCallback.Bind(idxA)
        MonitorTimers[idxA] := fn
        SetTimer(fn, Setups[idxA].CheckInterval > 0 ? Setups[idxA].CheckInterval : 5000)
    }

    ; DwmKeepAliveThumbs uses string keys
    keyA := "setup_" idxA, keyB := "setup_" idxB
    hA := DwmKeepAliveThumbs.Has(keyA), hB := DwmKeepAliveThumbs.Has(keyB)
    if (hA && hB) {
        temp := DwmKeepAliveThumbs[keyA]
        DwmKeepAliveThumbs[keyA] := DwmKeepAliveThumbs[keyB]
        DwmKeepAliveThumbs[keyB] := temp
    } else if (hA) {
        DwmKeepAliveThumbs[keyB] := DwmKeepAliveThumbs[keyA]
        DwmKeepAliveThumbs.Delete(keyA)
    } else if (hB) {
        DwmKeepAliveThumbs[keyA] := DwmKeepAliveThumbs[keyB]
        DwmKeepAliveThumbs.Delete(keyB)
    }
}

; Swap two entries in an index-keyed Map, handling cases where one or both may not exist.
SwapMapEntries(&theMap, a, b) {
    hasA := theMap.Has(a), hasB := theMap.Has(b)
    if (hasA && hasB) {
        temp := theMap[a]
        theMap[a] := theMap[b]
        theMap[b] := temp
    } else if (hasA) {
        theMap[b] := theMap[a]
        theMap.Delete(a)
    } else if (hasB) {
        theMap[a] := theMap[b]
        theMap.Delete(b)
    }
}

StartMonitor(idx) {
    global MonitorTimers, Setups

    if MonitorTimers.Has(idx)
        SetTimer(MonitorTimers[idx], 0)

    setup := Setups[idx]
    interval := setup.CheckInterval > 0 ? setup.CheckInterval : 5000

    monitorFn := MonitorCallback.Bind(idx)
    MonitorTimers[idx] := monitorFn
    SetTimer(monitorFn, interval)
}

MonitorCallback(idx) {
    global Setups, SetupStatuses, MonitoredTitles, MonitoredHwnds, MonitorTimers, Paused, EditorOpen, SetupHidden, SetupRunning

    if (Paused)
        return
    if (EditorOpen)
        return
    if (SetupRunning)
        return
    if (idx < 1 || idx > Setups.Length)
        return

    setup := Setups[idx]

    ; Auto-close batch window if it appears
    if (setup.CloseBatchTitle != "") {
        if WinExist(setup.CloseBatchTitle) {
            LogInfo("Closing background window for '" setup.Name "': " setup.CloseBatchTitle)
            try {
                WinClose(setup.CloseBatchTitle)
                if !WinWaitClose(setup.CloseBatchTitle,, 1)
                    WinKill(setup.CloseBatchTitle)
            }
        }
    }

    ; Skip title check and recovery for hidden windows — they're intentionally off-screen
    isHidden := SetupHidden.Has(idx) && SetupHidden[idx]

    ; Check if window still exists
    windowGone := true
    if MonitoredHwnds.Has(idx) {
        hwnd := MonitoredHwnds[idx]
        if WinExist("ahk_id " hwnd)
            windowGone := false
    } else {
        monTitle := MonitoredTitles.Has(idx) ? MonitoredTitles[idx] : Setups[idx].WindowTitle
        if (monTitle != "" && WinExist(monTitle))
            windowGone := false
    }

    if (windowGone) {
        ; Window disappeared - relaunch
        LogInfo("Window gone for setup #" idx " (" Setups[idx].Name "), relaunching")
        SetupStatuses[idx] := "Relaunching..."
        RefreshMainLV()
        if MonitorTimers.Has(idx)
            SetTimer(MonitorTimers[idx], 0)
        Sleep(1000)
        RunSetup(idx)
        return
    }

    ; Skip title check for hidden windows — don't interfere with off-screen state
    if (isHidden)
        return

    ; Window exists — check if title still matches expected (detect wrong screen)
    if MonitoredHwnds.Has(idx) && MonitoredTitles.Has(idx) {
        expectedTitle := MonitoredTitles[idx]
        if (expectedTitle = "")
            return
        try {
            currentTitle := WinGetTitle("ahk_id " MonitoredHwnds[idx])
            if (currentTitle != expectedTitle) {
                ; Title changed — window is on the wrong screen, recover
                LogInfo("Title mismatch for setup #" idx " (" Setups[idx].Name "), recovering: expected '" expectedTitle "' got '" currentTitle "'")
                SetupStatuses[idx] := "Recovering..."
                RefreshMainLV()
                if MonitorTimers.Has(idx)
                    SetTimer(MonitorTimers[idx], 0)
                CloseSetupWindow(idx)
                StopSetup(idx)
                Sleep(1000)
                RunSetup(idx)
                return
            }
        }
    }
}

; ============================================================================
; Auto-Refresh Check
; ============================================================================
CheckAutoRefreshReady() {
    global AutoRefresh, RefreshActive, Setups, SetupStatuses

    if (!AutoRefresh || RefreshActive)
        return

    ; Check if ANY setup is still launching or pending
    for idx, setup in Setups {
        status := SetupStatuses.Has(idx) ? SetupStatuses[idx] : "Stopped"
        ; If any setup is mid-launch, not ready yet
        if (status = "Launching..." || status = "Step Timeout" || status = "Relaunching...")
            return
    }

    ; Check that at least one setup is running/monitoring
    hasActive := false
    for idx, setup in Setups {
        status := SetupStatuses.Has(idx) ? SetupStatuses[idx] : "Stopped"
        if (status = "Running" || status = "Monitoring") {
            hasActive := true
            break
        }
    }

    if (hasActive)
        StartRefreshCycle()
}

; ============================================================================
; Hide / Show Window
; ============================================================================

; Get X position that keeps 1 pixel of a window on-screen (for DWM live capture)
; Matches LiveView.ahk method — finds leftmost monitor edge, positions window so 1px remains
GetBarelyOffScreenX(windowWidth) {
    leftEdge := 0
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &mLeft)
        if (A_Index = 1 || mLeft < leftEdge)
            leftEdge := mLeft
    }
    return leftEdge - windowWidth + 1
}

; Ensure the hidden keep-alive GUI exists (hosts DWM thumbnails to keep rendering alive)
EnsureKeepAliveGui() {
    global DwmKeepAliveGui
    if (DwmKeepAliveGui = "") {
        DwmKeepAliveGui := Gui("+ToolWindow -Caption", "DWM KeepAlive")
        ; Must be visible (not SW_HIDE) for DWM to consider thumbnails active
        ; Off-screen at -9999 so user never sees it
        DwmKeepAliveGui.Show("x-9999 y-9999 w1 h1 NoActivate")
    }
}

; Register a DWM thumbnail to keep the source window rendered by DWM while off-screen
RegisterKeepAliveThumb(key, sourceHwnd) {
    global DwmKeepAliveThumbs, DwmKeepAliveGui
    EnsureKeepAliveGui()

    ; Unregister existing if any
    UnregisterKeepAliveThumb(key)

    thumb := 0
    hr := DllCall("dwmapi\DwmRegisterThumbnail", "Ptr", DwmKeepAliveGui.Hwnd, "Ptr", sourceHwnd, "Ptr*", &thumb, "UInt")
    if (hr = 0 && thumb) {
        DwmKeepAliveThumbs[key] := thumb
        ; Set thumbnail properties — tiny 1x1 rendering, invisible but keeps DWM alive
        props := Buffer(48, 0)
        NumPut("UInt", 0x1F, props, 0)     ; flags: all fields valid
        NumPut("Int", 0, props, 4)          ; dest left
        NumPut("Int", 0, props, 8)          ; dest top
        NumPut("Int", 1, props, 12)         ; dest right
        NumPut("Int", 1, props, 16)         ; dest bottom
        NumPut("Int", 0, props, 20)         ; src left
        NumPut("Int", 0, props, 24)         ; src top
        NumPut("Int", 1, props, 28)         ; src right
        NumPut("Int", 1, props, 32)         ; src bottom
        NumPut("UChar", 0, props, 36)       ; opacity 0 (invisible)
        NumPut("Int", 1, props, 40)         ; visible
        NumPut("Int", 1, props, 44)         ; source client area only
        DllCall("dwmapi\DwmUpdateThumbnailProperties", "Ptr", thumb, "Ptr", props)
    }
}

UnregisterKeepAliveThumb(key) {
    global DwmKeepAliveThumbs
    if DwmKeepAliveThumbs.Has(key) {
        try DllCall("dwmapi\DwmUnregisterThumbnail", "Ptr", DwmKeepAliveThumbs[key])
        DwmKeepAliveThumbs.Delete(key)
    }
}

HideSetupWindow(idx) {
    global MonitoredHwnds, HiddenPositions, SetupHidden

    if !MonitoredHwnds.Has(idx)
        return
    if (SetupHidden.Has(idx) && SetupHidden[idx])
        return

    hwnd := MonitoredHwnds[idx]
    if !WinExist(hwnd)
        return

    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        ; If window is already off-screen (e.g. from a previous session), treat as already hidden
        if (x < -(w / 2)) {
            screenW := A_ScreenWidth
            screenH := A_ScreenHeight
            restoreX := (screenW - w) // 2
            restoreY := (screenH - h) // 2
            HiddenPositions[idx] := {x: restoreX, y: restoreY, w: w, h: h}
            SetupHidden[idx] := true
            RegisterKeepAliveThumb("setup_" idx, hwnd)
            return
        }
        HiddenPositions[idx] := {x: x, y: y, w: w, h: h}
        ; Register DWM keep-alive thumbnail BEFORE moving off-screen
        RegisterKeepAliveThumb("setup_" idx, hwnd)
        WinMove(GetBarelyOffScreenX(w), y,,, hwnd)
        SetupHidden[idx] := true
    }
}

ShowSetupWindow(idx) {
    global MonitoredHwnds, HiddenPositions, SetupHidden

    if !MonitoredHwnds.Has(idx)
        return
    if (!SetupHidden.Has(idx) || !SetupHidden[idx])
        return

    hwnd := MonitoredHwnds[idx]
    if !WinExist(hwnd)
        return

    if HiddenPositions.Has(idx) {
        pos := HiddenPositions[idx]
        try WinMove(pos.x, pos.y,,, hwnd)
        HiddenPositions.Delete(idx)
    }
    UnregisterKeepAliveThumb("setup_" idx)
    SetupHidden[idx] := false
}

OnToggleHide(*) {
    global SetupHidden, MainLV
    row := MainLV.GetNext(0)
    if (row = 0) {
        MsgBox("Please select a setup to hide or show.", APP_NAME, "Icon!")
        return
    }
    if (SetupHidden.Has(row) && SetupHidden[row])
        ShowSetupWindow(row)
    else
        HideSetupWindow(row)
}

; ============================================================================
; Refresh Cycle Logic
; ============================================================================
StartRefreshCycle() {
    global RefreshActive, RefreshTimerFn, RefreshCountdownFn
    global RefreshSecondsLeft, RefreshCount, RefreshInterval
    global AutoShowCountdown, AutoHideCountdown

    if (RefreshActive)
        StopRefreshCycle()

    RefreshActive := true
    RefreshCount := 0
    RefreshSecondsLeft := RefreshInterval

    ; Countdown tick every 1 second
    RefreshCountdownFn := RefreshCountdownTick
    SetTimer(RefreshCountdownFn, 1000)

    ; Execution timer
    RefreshTimerFn := ExecuteRefreshCycle
    SetTimer(RefreshTimerFn, RefreshInterval * 1000)

    UpdateStatusBar()

    ; Auto-show the countdown GUI if option is enabled (deferred to avoid call-stack issues)
    if (AutoShowCountdown)
        SetTimer(AutoShowCountdownDeferred, -200)
}

AutoShowCountdownDeferred() {
    global AutoHideCountdown
    ShowCountdownGui()
    ; Auto-hide off-screen if that option is also enabled
    if (AutoHideCountdown)
        SetTimer(OnHideCountdown, -300)
}

StopRefreshCycle() {
    global RefreshActive, RefreshTimerFn, RefreshCountdownFn

    if (RefreshTimerFn != "") {
        SetTimer(RefreshTimerFn, 0)
        RefreshTimerFn := ""
    }
    if (RefreshCountdownFn != "") {
        SetTimer(RefreshCountdownFn, 0)
        RefreshCountdownFn := ""
    }

    RefreshActive := false
    UpdateStatusBar()
    UpdateCountdownGui()
}

RefreshCountdownTick() {
    global RefreshSecondsLeft, RefreshInterval, Paused, EditorOpen, SetupRunning

    if (Paused)
        return

    ; Pause countdown when setups with refresh steps aren't ready
    if (EditorOpen || SetupRunning || !AnyRefreshSetupReady()) {
        UpdateStatusBar()
        UpdateCountdownGui()
        return
    }

    RefreshSecondsLeft -= 1
    if (RefreshSecondsLeft < 0)
        RefreshSecondsLeft := RefreshInterval

    UpdateStatusBar()
    UpdateCountdownGui()
}

AnyRefreshSetupReady() {
    global Setups, SetupStatuses
    for idx, setup in Setups {
        if (setup.RefreshSteps.Length = 0)
            continue
        status := SetupStatuses.Has(idx) ? SetupStatuses[idx] : "Stopped"
        if (status = "Running" || status = "Monitoring")
            return true
    }
    return false
}

ExecuteRefreshCycle() {
    global Setups, SetupStatuses, MonitoredTitles, MonitoredHwnds
    global RefreshCount, RefreshSecondsLeft, RefreshInterval, Paused, EditorOpen, SetupRunning
    global SetupHidden, HiddenPositions

    if (Paused)
        return
    if (EditorOpen)
        return
    if (SetupRunning)
        return

    RefreshCount += 1
    RefreshSecondsLeft := RefreshInterval

    ; Collect setups that need recovery after refresh failure
    failedSetups := []

    ; Block physical input during refresh to prevent interference
    try BlockInput("SendAndMouse")
    try BlockInput("MouseMove")

    try {
        for idx, setup in Setups {
            if (setup.RefreshSteps.Length = 0)
                continue

            status := SetupStatuses.Has(idx) ? SetupStatuses[idx] : "Stopped"
            if (status != "Running" && status != "Monitoring")
                continue

            isHidden := SetupHidden.Has(idx) && SetupHidden[idx]

            ; Only activate visible windows — hidden windows get ControlSend only
            if (!isHidden) {
                activated := false
                if MonitoredHwnds.Has(idx) {
                    hwnd := MonitoredHwnds[idx]
                    if WinExist("ahk_id " hwnd) {
                        try {
                            WinActivate("ahk_id " hwnd)
                            activated := true
                        }
                    }
                }
                if (!activated) {
                    monTitle := MonitoredTitles.Has(idx) ? MonitoredTitles[idx] : setup.WindowTitle
                    if (monTitle = "" || !WinExist(monTitle))
                        continue
                    try WinActivate(monTitle)
                }
                Sleep(300)
            }

            ; Execute refresh steps — send directly to HWND
            rHwnd := MonitoredHwnds.Has(idx) ? MonitoredHwnds[idx] : 0
            stepFailed := false
            for _, step in setup.RefreshSteps {
                if (step.Mode = "delay") {
                    delay := IsNumber(step.Value) ? Integer(step.Value) : 500
                    Sleep(delay)
                } else if (step.Mode = "window") {
                    if !WinWait(step.Value,, 15) {
                        stepFailed := true
                        break
                    }
                    if (!isHidden) {
                        WinActivate(step.Value)
                        Sleep(200)
                    }
                }

                try {
                    if (!isHidden) {
                        ; SendEvent with key delay for reliable modifier combos
                        if (rHwnd) {
                            WinActivate("ahk_id " rHwnd)
                            Sleep(100)
                        }
                        prevDelay := A_KeyDelay
                        prevDuration := A_KeyDuration
                        SetKeyDelay(30, 30)
                        SendEvent("{Ctrl up}{Shift up}{Alt up}")
                        Sleep(30)
                        SendEvent(step.Key)
                        SetKeyDelay(prevDelay, prevDuration)
                    } else if (rHwnd) {
                        ; Hidden windows: ControlSend is the only option
                        ControlSend(step.Key,, "ahk_id " rHwnd)
                    } else {
                        stepFailed := true
                        break
                    }
                } catch {
                    ; Fallback to ControlSend for visible windows
                    if (rHwnd) {
                        try {
                            ControlSend(step.Key,, "ahk_id " rHwnd)
                        } catch {
                            stepFailed := true
                            break
                        }
                    } else {
                        stepFailed := true
                        break
                    }
                }
            }

            ; Re-hide window if app repositioned itself during refresh
            if (isHidden && rHwnd) {
                try {
                    WinGetPos(&cx, &cy, &cw, , rHwnd)
                    if (cx > -10)
                        WinMove(GetBarelyOffScreenX(cw), cy,,, rHwnd)
                }
            }

            if (stepFailed)
                failedSetups.Push(idx)
        }
    } finally {
        try BlockInput("Default")
    try BlockInput("MouseMoveOff")
    }

    ; Recover failed setups — close window and re-run full setup
    for _, failIdx in failedSetups {
        SetupStatuses[failIdx] := "Recovering..."
        RefreshMainLV()
        CloseSetupWindow(failIdx)
        StopSetup(failIdx)
        Sleep(1000)
        RunSetup(failIdx)
    }

    UpdateStatusBar()
    UpdateCountdownGui()
}

UpdateStatusBar() {
    global TxtStatusBar, RefreshActive, RefreshSecondsLeft, RefreshCount, Paused
    global EditorOpen, SetupRunning

    pausePrefix := Paused ? "  PAUSED  |  " : "  "
    if (!RefreshActive) {
        TxtStatusBar.Value := pausePrefix "Refresh: Off"
    } else if (!Paused && (EditorOpen || SetupRunning || !AnyRefreshSetupReady())) {
        TxtStatusBar.Value := ""
    } else {
        mins := RefreshSecondsLeft // 60
        secs := Mod(RefreshSecondsLeft, 60)
        timeStr := mins > 0 ? Format("{:d}m {:02d}s", mins, secs) : Format("{:d}s", secs)
        TxtStatusBar.Value := pausePrefix "Next refresh in: " timeStr "  |  Count: " RefreshCount
    }
}

; ============================================================================
; Floating Countdown GUI
; ============================================================================
ShowCountdownGui() {
    global CountdownGui, CountdownTxtTime, CountdownTxtCount, CountdownVisible, CountdownHidden, CountdownSavedPos

    ; If hidden off-screen, restore it
    if (CountdownVisible && CountdownHidden) {
        RestoreCountdownGui()
        return
    }

    if (CountdownVisible) {
        try CountdownGui.Show()
        return
    }

    CountdownGui := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox -MaximizeBox", "Refresh Timer")
    CountdownGui.SetFont("s10", "Segoe UI")
    CountdownGui.BackColor := "1A1A2E"

    CountdownGui.SetFont("s20 Bold", "Segoe UI")
    CountdownTxtTime := CountdownGui.AddText("xm ym w220 h40 cWhite Center", "--")

    CountdownGui.SetFont("s10 Norm", "Segoe UI")
    CountdownTxtCount := CountdownGui.AddText("xm y+5 w220 h22 c888888 Center", "Count: 0")

    btnHideCountdown := CountdownGui.AddButton("xm y+8 w220 h24", "Hide")
    btnHideCountdown.OnEvent("Click", OnHideCountdown)

    CountdownGui.OnEvent("Close", OnCountdownClose)
    CountdownGui.Show("w250 h120")
    CountdownVisible := true
    CountdownHidden := false
    UpdateCountdownGui()
}

HideCountdownGui() {
    global CountdownGui, CountdownVisible, CountdownHidden, CountdownSavedPos
    if (CountdownVisible) {
        UnregisterKeepAliveThumb("countdown")
        try CountdownGui.Destroy()
        CountdownVisible := false
        CountdownHidden := false
        CountdownSavedPos := ""
    }
}

OnCountdownClose(*) {
    HideCountdownGui()
}

OnHideCountdown(*) {
    global CountdownGui, CountdownHidden, CountdownSavedPos
    if (CountdownHidden)
        return
    try {
        hwnd := CountdownGui.Hwnd
        WinGetPos(&x, &y, &w, &h, hwnd)
        CountdownSavedPos := {x: x, y: y, w: w, h: h}
        ; Register DWM keep-alive thumbnail BEFORE moving off-screen
        RegisterKeepAliveThumb("countdown", hwnd)
        WinMove(GetBarelyOffScreenX(w), y,,, hwnd)
        CountdownHidden := true
    }
}

RestoreCountdownGui() {
    global CountdownGui, CountdownHidden, CountdownSavedPos
    if (!CountdownHidden)
        return
    try {
        if (CountdownSavedPos != "") {
            WinMove(CountdownSavedPos.x, CountdownSavedPos.y,,, CountdownGui.Hwnd)
        }
        UnregisterKeepAliveThumb("countdown")
        CountdownHidden := false
        CountdownSavedPos := ""
    }
}

UpdateCountdownGui() {
    global CountdownVisible, CountdownTxtTime, CountdownTxtCount
    global RefreshActive, RefreshSecondsLeft, RefreshCount
    global Paused, EditorOpen, SetupRunning

    if (!CountdownVisible)
        return

    if (!RefreshActive) {
        try {
            CountdownTxtTime.Value := "OFF"
            CountdownTxtCount.Value := "Count: " RefreshCount
        }
        return
    }

    if (!Paused && (EditorOpen || SetupRunning || !AnyRefreshSetupReady())) {
        try {
            CountdownTxtTime.Value := ""
            CountdownTxtCount.Value := ""
        }
        return
    }

    mins := RefreshSecondsLeft // 60
    secs := Mod(RefreshSecondsLeft, 60)
    timeStr := mins > 0 ? Format("{:d}m {:02d}s", mins, secs) : Format("{:d}s", secs)
    try {
        CountdownTxtTime.Value := timeStr
        CountdownTxtCount.Value := "Count: " RefreshCount
    }
}

; ============================================================================
; Tray Menu
; ============================================================================
BuildTrayMenu() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Show " APP_NAME, OnTrayShow)
    tray.Add()
    tray.Add("Run All Auto-Start", OnTrayRunAutoStart)
    tray.Add()
    tray.Add("Help", OnShowHelp)
    tray.Add("View Log", OnTrayViewLog)
    tray.Add()
    tray.Add("Exit", OnTrayExit)
    tray.Default := "Show " APP_NAME
}

OnTrayShow(*) {
    MainGui.Show()
}

OnTrayRunAutoStart(*) {
    OnRunAllAutoStart()
}

OnTrayViewLog(*) {
    if FileExist(LOG_FILE)
        Run('notepad.exe "' LOG_FILE '"')
    else
        MsgBox("No log file found yet.", APP_NAME, "Icon!")
}

OnTrayExit(*) {
    CleanupAndExit()
}

CleanupAndExit() {
    global DwmKeepAliveThumbs, DwmKeepAliveGui
    LogInfo("=== " APP_NAME " exiting ===")
    ; Prevent all timer interrupts during shutdown to avoid corrupt saves
    Critical("On")
    try BlockInput("Default")
    try BlockInput("MouseMoveOff")
    ; Stop deferred timers
    try SetTimer(AutoShowCountdownDeferred, 0)
    try SetTimer(OnHideCountdown, 0)
    StopRefreshCycle()
    for idx, fn in MonitorTimers {
        SetTimer(fn, 0)
    }
    ; Unregister all DWM keep-alive thumbnails
    for key, thumb in DwmKeepAliveThumbs {
        try DllCall("dwmapi\DwmUnregisterThumbnail", "Ptr", thumb)
    }
    DwmKeepAliveThumbs := Map()
    if (DwmKeepAliveGui != "") {
        try DwmKeepAliveGui.Destroy()
        DwmKeepAliveGui := ""
    }
    ExitApp()
}

; Kill switch: Ctrl+Shift+Esc to immediately exit
^+Escape::CleanupAndExit()
; Pause toggle: Ctrl+Shift+P
^+p::OnTogglePause()
; Close all: Ctrl+Shift+Q
^+q::OnCloseAllSetups()
; Stop all: Ctrl+Shift+S
^+s::OnStopAllSetups()

; ============================================================================
; Startup
; ============================================================================

LogInfo("=== " APP_NAME " starting ===")
try BlockInput("Default")
    try BlockInput("MouseMoveOff")  ; Clear any leftover BlockInput from previous crash
LoadAllSetups()
LogInfo("Loaded " Setups.Length " setups")
BuildMainGui()
BuildTrayMenu()
RefreshMainLV()
MainGui.Show("w700 h630")

; Auto-show countdown GUI at launch if setting is enabled
if (AutoShowCountdown) {
    ShowCountdownGui()
    if (AutoHideCountdown)
        SetTimer(OnHideCountdown, -300)
}

; Auto-start setups sequentially (avoids conflicts between same-app launches)
RunAutoStartSequential(checkGlobal := true) {
    global GlobalAutoStart
    if (checkGlobal && !GlobalAutoStart)
        return
    for idx, setup in Setups {
        if (setup.AutoStart)
            RunSetup(idx)
    }
}
SetTimer(RunAutoStartSequential, -500)
