''================================PID V4  + Connect========================================
'' Qic PID Object nov 2010 HJK
'' V1 is more generic. The PID controller only does configurable number of PID-loops.
'' V2 implements separate position and velocity feedback
'' V3 Fe added, open loop added
'' Based on PID V3, but this version includes the QiK connection in one loop to save a Cog

'' Controls max 8 motors in velocity mode or position mode via a QiK drive (Pololu 12V10)
'' 
'' Performance in Spin: Velocity control in 8  PID loop at 3400 us for PID and 10500 us for I/O
'' Tested with 8 PID loops at 50 Hz
''
'' Febr 2011: Following error check and setpoint min max settings added and axis shut down on FE
'' Mar 2011 : In position window added
'' May 2011 : Open loop mode added, Scale factors for pos vel and output added
'' July 2011: I/O included in the loop to save performance. The effect is, that the I/O sectoins needs modification
'' if more or less control loops are added.
'' June 2013 5.4: Invert output and invert encoder added. Velocity limit and Accelleration added
'' Sept 2015 Maxvelocity per PID cycle from 20 to 40 to accomodate higher platform velocities

''=============================================================================

CON        


  PIDLed = 27         'PID test led

  PIDCnt = 2          'Max PID loop count

  _1ms  = 1_000_000 / 1_000          'Divisor for 1 ms

  cIlimit = 30000         'I- action limiter
  Outlimit = 127          'Output limiter

  nPIDLoops = 2           'Number of PID loops configured
  MotorCnt = nPIDLoops

  Drive0   = 10           ' Drive 0 address, 2 motor per address

    
OBJ
  t             : "Timing"
  QiK           : "QiKCommands"                         ' Standard serial for drives
  PosEnc        : "Quadrature Encoder"                  ' Position Encoder object

Var Long PotmValue0
    long s, ms, us
    
    Long SetpAddr
    Long lActPos[PIDCnt], lActVelPos[PIDCnt], lActVel[PIDCnt], EncPos[PIDCnt]   'Actual position and velocity
    Long PosScale[PIDCnt], VelScale[PIDCnt], OutputScale[PIDCnt]
    Long PIDMode[PIDCnt]                 'PID loop mode: 0= open 1 = Vel loop 2 = Pos loop
    Long DeltaSetp[PIDCnt], Setp[PIDCnt], lSetp[PIDCnt], SetVel[PIDCnt], preSetVel[PIDCnt]

   'PID parameters
    Long PIDMax, K[PIDCnt], KI[PIDCnt], Kp[PIDCnt], Acc[PIDCnt], MaxVel[PIDCnt], F
    Long InvertPosition, InvertVelocity, InvertOutput
    Long ILimit[PIDCnt], lI[PIDCnt], OpenLoopCmd[PIDCnt]
    Long PrevEncPos[PIDCnt], DVT[PIDCnt], DPT[PIDCnt]
    Long PIDStack[400]
    Long PIDTime, lPeriod, PIDLeadTime, LedMode
    Long PIDCog, PIDStatus, PIDBusy, PIDCyclesPerSec
    Word PIDCntr
    Long Pos[MotorCnt], Vel[MotorCnt], Input[MotorCnt], Output[MotorCnt]
    Long ActCurrent[PIDCnt], MaxCurrent[PIDCnt], MaxSetCurrent[PIDCnt], CurrError[PIDCnt], AnyCurrError

    'Encoder vars
    Long  EncCog, EncCntr
 
    'QiK I/O parameters
    Long QiKCog, LastErr, lQikTxd, lQikRxd  'Qik serial connection pins
    Long Err[PIDCnt]                     'Last error in drive


    'Limits
    Long SetpMaxPlus[PIDCnt], SetpMaxMin[PIDCnt], FE[PIDCnt], FEMax[PIDCnt], FETrip[PIDCnt], FEAny
    Long InPosWindow[PIDCnt], InPos[PIDCnt]

    Long MAEState, mMAEPos, mMAEOffset, mEnc0Pin, lEncCnt
        
' ----------------  Stop PID loop -----
{PUB PIDStop
  CogStop(PIDCog)

' ----------------  Start PID loop -----
PUB PIDStart
  PIDCog:=CogNew(PID(lPeriod), @PIDStack)
Return PIDCog
 }
'--------------------------- Start QiC PID --------------------------------
'With Period in ms 
' oud PUB Start(Period, aEncPos, alActVel, aSetp, aOutput, lPIDCnt)
'PUB Start(Period, aSetp, aMAEPos, aMAEOffset, aEnc0Pin, aEncCnt, aQikTxd, aQikRxd, lPIDCnt)
PUB Start(Period, aSetp,aEnc0Pin, aEncCnt, aQikTxd, aQikRxd, lPIDCnt)

  PIDMax := lPIDCnt-1    'Calculate loop max PID
'  mMAEPos:=aMAEPos   'Store addres MAE abs encoder data
'  mMAEOffset:=aMAEOffset
  mEnc0Pin:=aEnc0Pin
  lEncCnt:=aEncCnt
  lQikTxd:=aQikTxd
  lQikRxd:=aQikRxd
  lPeriod:=Period                  'Save PID cycle time

'  EncPosAddr  := aEncPos                  'Save PID input and output addresses
'  lActVelAddr  := alActVel
   SetpAddr := aSetp
'  MOutput   := aOutPut

  EncCog:=PosEnc.start(mEnc0Pin, lEncCnt, 0, @EncPos) 'Start quadrature encoder  thr4
  
  PIDCog:=CogNew(PID(lPeriod), @PIDStack)       'Start PID loop at 20 ms rate    thr5
  PIDMode:=1
  PIDCyclesPerSec:=1000/Period

  QikCog:=QiK.Init(lQikRxd, lQikTxd) 'Start QiK serial communication             thr 6 en 7
  QiK.SetProtocol(1)                 'Enable QiK protocol
  
Return QikCog
  

' ----------------  PID loop ---------------------------------------
PRI PID(Period) | i, T1, T2, ClkCycles, LSetPos, ActRVel ' Cycle runs every Period ms

    dira[PIDLed]~~                 'Set I/O pin for LED to output…
    Period:= 1 #> Period <# 1000   'Limit PID period
    PIDStatus:=1
    ClkCycles := ((clkfreq / _1ms * Period) - 4296) #> 381   'Calculate 1 ms time unit
    Repeat i from 0 to PIDMax                 'Init temp vars
'      PrevEncPos[i]:=Long[EncPosAddr][i]
      PrevEncPos[i]:=EncPos[i]
      K[i]:= 1000                        'Loop gain Prop velocity 
      KI[i]:=50                          'Loop gain I- action velocity loop
      Kp[i]:=1000                        'Loop gain Position loop
      PosScale[i]:=1                     'Pos scale factor. Divides pos encoder input
      VelScale[i]:=1                     'Vel scale factor. Divides vel encoder input
      OutputScale[i]:=1                  'Vel scale factor. Divides vel encoder input
      Acc[i]:=1                          'Default acc value
      MaxVel[i]:=40                      'Default Max vel
      ILimit[i]:=cIlimit                 'I action limit
      FEMax[i]:=1100                     'Following error limit
      InPosWindow[i]:=100                'In position window
      PIDMode[i]:=0                      'All open loop
      MaxCurrent[i]:=1000                'Max current 1000 mA
      InvertPosition[i]:=1                'All non inverted
      InvertVelocity[i]:=1
      InvertOutput[i]:=1
      
    PIDStatus:=2                         'PID Init done
    F:=1000  
    T1:=Cnt
    !outa[PIDLed]                        'Toggle I/O Pin for debug
                                         
    PIDStatus:=3                         'PID running 

    Repeat                               'Main loop     Volgfout!!
      Repeat i from 0 to PIDMax          'Cycle through the loops
        T2:=Cnt
                                       'Connect sensor inputs
        lActPos[i]:= InvertPosition * EncPos[i]      'PID 0 Wheel Front Right
        lActVelPos[i]:= InvertVelocity * EncPos[i]   'Velocity input loop 0
        Setp[i]:=long[SetpAddr][i]

'        lActVel[i]:=(Long[lActVelAddr][i]/VelScale[i] - PrevEncPos[i])*F 'Calculate velocities M0 - M3 from delta position
        lActVel[i]:=(lActVelPos[i]/VelScale[i] - PrevEncPos[i])*F 'Calculate velocities M0 - M3 from delta position
'        PrevEncPos[i]:=Long[lActVelAddr][i]/VelScale[i]
        PrevEncPos[i]:=lActVelPos[i]/VelScale[i]

        Case PIDMode[i]                        'Process various PID modes
'          -2: Long[MOutput][i]:=OpenLoopCmd[i] 'Open loop output command
          -2: Output[i]:=OpenLoopCmd[i]         'Open loop output command
              LedMode:=10
'          -1,0: Long[MOutput][i]:=0            'Open loop and in brake mode
          -1,0: Output[i]:=0                                                    'Open loop and in brake mode
             SetVel[i]:=0
             lI[i]:=0
             FE[i]:=0
             InPos[i]:=false
             LedMode:=20                        'Slow blink

'          3: lSetPos:= Long[SetpAddr][i]       'current set position for limiter calculation
'             FE[i]:= Long[SetpAddr][i] - Long[EncPosAddr][i]/PosScale[i]
          3: FE[i]:= Setp[i] - lActPos[i]/PosScale[i]                           'Current set position for limiter calculation
             FETrip[i]:= FETrip[i] or (||FE[i] > FEMax[i])                      'Keep FE trip even if error disappears
             FEAny:=FEAny OR FETrip[i]
             InPos[i]:=(||FE[i] < InPosWindow[i])                               'Check in position of axis
             SetVel[i]:= -MaxVel[i] #> ( FE[i] * Kp[i]/1000) <# MaxVel[i]
             DVT[i]:= (SetVel[i]*100-lActVel[i]) / F                            'Delta Velocity
             LedMode:=3                        'Slow blink

'          2: FE[i]:= Long[SetpAddr][i] - Long[EncPosAddr][i]/PosScale[i]
          2: FE[i]:= Setp[i] - lActPos[i]/PosScale[i]                           'Pos mode No velocity limiter 
             FETrip[i]:= FETrip[i] or (||FE[i] > FEMax[i])                      'Keep FE trip even if error disappears
             FEAny:=FEAny OR FETrip[i]
             InPos[i]:=(||FE[i] < InPosWindow[i])                               'Check in position of axis
             SetVel[i]:= FE[i]  * Kp[i]/1000   'Position mode
             DVT[i]:= (SetVel[i]*100-lActVel[i]) / F                            'Delta Velocity
             LedMode:=4                        'Slow blink

'          1: SetVel[i]:= Long[SetpAddr][i]                                     'Velocity mode
          1: DeltaSetp[i]:=-Acc[i] #> (Setp[i] - SetVel[i]) <# Acc[i]            'Limited speed delta
             lSetp[i]:=SetVel[i]+ DeltaSetp[i]
             SetVel[i]:= -MaxVel[i] #> lSetp[i]  <# MaxVel[i]                    'Velocity limiter
'             SetVel[i]:= -MaxVel[i] #> Setp[i]  <# MaxVel[i]                    'Velocity limiter
             DVT[i]:= (SetVel[i]*F-lActVel[i]) / F                              'Delta Velocity
             FE[i]:=0
             LedMode:=7                        'Slow blink

        if PIDMode[i]>0                                       'The actual control loop
          lI[i]:= -Ilimit[i] #> (lI[i]+DVT[i]) <# Ilimit[i]   'Limit I-action
'          PIDBusy:=1

           if FETrip[i]
             PIDMode[i]:=0     'Set loop open on FE

'          Long[MOutput][i]:=-Outlimit #> (DVT[i]*K[i] + lI[i]*KI[i]) / (F*OutputScale[i]) <# Outlimit 'Calculate limited PID Out
          Output[i]:=InvertOutput * (-Outlimit #> (DVT[i]*K[i] + lI[i]*KI[i]) / (F*OutputScale[i]) <# Outlimit) 'Calculate limited PID Out

        case i
           0: qik.SetSpeedM0(Drive0, Output[0])
              LastErr:=qik.GetError(Drive0)              'Get drive errors if any and clear error flag
              if LastErr>0
                Err[0]:=LastErr
              ActCurrent[0]:=qik.GetCurrentM0(Drive0)    'Get motor 0 current

           1: qik.SetSpeedM1(Drive0, Output[1])
              ActCurrent[1]:=qik.GetCurrentM1(Drive0)    'Get motor 1 current

        MaxCurrent[i] #>= ActCurrent[i]  'Check for current overload 
        CurrError[i]:= CurrError[i] or (ActCurrent[i] > MaxSetCurrent[i])  'Check if any current limit exceeded set alarm if exceeded
        AnyCurrError:= AnyCurrError or CurrError[i]                  'Check if any current error

        PIDLeadTime:=Cnt-T2


      PIDTime:=Cnt-T1                    'Measure actual loop time in clock cycles
      waitcnt(ClkCycles + T1)            'Wait for designated time
      PIDCntr++                          'Update PIDCounter               
      if (PIDCntr//LedMode)==0
        !outa[PIDLed]                      'Toggle I/O Pin for debug
      T1:=Cnt

' ----------------  Brake wheels  ---------------------------------------
PUB BrakeWheels(BrakeValue) | lB
'   DisableWheels                               'Disable wheels before braking
  SetPIDMode(0,-1)
  SetPIDMode(2,-1)                    
  lB:= BrakeValue '0 #> BrakeValue <# 127 
  QiK.SetBrakeM0(Drive0,lB)                     'Brake wheels
  QiK.SetBrakeM1(Drive0,lB)                     
                    


' ---------------- 'Get Qik Pins and baud -------------------------------
PUB GetQikRxTxPins 
Return Qik.GetRxTxPins

' ---------------- 'Reset current errors -------------------------------
PUB ResetCurrError | i
  repeat i from 0 to PIDMax
    CurrError[i]:=false
    AnyCurrError[i]:=false
    CurrError:=0
    MaxCurrent[i]:=0

' ---------------- 'Reset max current -------------------------------
PUB ResetMaxCurrent | i
  repeat i from 0 to PIDMax
    MaxCurrent[i]:=0

' ----------------  Clear errors of drives ---------------------------------------
PUB ClearErrors | i 
  repeat i from 0 to PIDMax
    Err[i]:=0
    
' ----------------------- Public functions -----------------------
' ---------------------  Set In pos Window -----------------------------
'Invert values for PID controller inputs and output
PUB SetInvert(i,lInvertPosition, lInvertVelocity, lInvertOutput)  ' #pid, position, velocity, output 
  i:= 0 #> i <# PIDMax
  InvertPosition:=lInvertPosition
  InvertVelocity:=lInvertVelocity
  InvertOutput:=lInvertOutput

  
PUB SetInPosWindow(i,lInPosWindow)
  i:= 0 #> i <# PIDMax
  InPosWindow[i]:=lInPosWindow

' ---------------------  Get In pos Window ---------------------------
PUB GetInPosWindow(i)
  i:= 0 #> i <# PIDMax
Return InPosWindow[i]

' ---------------------  Get In pos ------- ---------------------------
PUB GetInPos(i)
  i:= 0 #> i <# PIDMax
Return InPos[i]

' ---------------------  Set Setpoint Max Min -----------------------------
PUB SetSetpMaxMin(i,lSetpMaxMin)
  i:= 0 #> i <# PIDMax
  SetpMaxMin[i]:=lSetpMaxMin
  
' ---------------------  Get Setpoint Max Min ---------------------------
PUB GetSetpMaxMin(i)
  i:= 0 #> i <# PIDMax
Return SetpMaxMin[i]
' ---------------------  Set Setpoint Max Plus -----------------------------
PUB SetSetpMaxPlus(i,lSetpMaxPlus)
  i:= 0 #> i <# PIDMax
  SetpMaxPlus[i]:=lSetpMaxPlus
  
' ---------------------  Get Setpoint Max Plus---------------------------
PUB GetSetpMaxPlus(i)
  i:= 0 #> i <# PIDMax
Return SetpMaxPlus[i]

' ---------------------  Get Setpoint ----------------------------------
PUB GetSetp(i)
  i:= 0 #> i <# PIDMax
Return Setp[i]

' --------------------- Reset FolErr Trip -----------------------------
PUB ResetFETrip(i)
  i:= 0 #> i <# PIDMax
  FETrip[i]:=0
  
' --------------------- Reset All FolErr Trip -----------------------------
PUB ResetAllFETrip | i
  repeat i from 0 to PIDMax
    FETrip[i]:=false
  FeAny:=false  

' --------------------- Set Max FolErr -----------------------------
PUB SetFEMax(i,lFEMax)
  i:= 0 #> i <# PIDMax
  FEMax[i]:=lFEMax
  
' ---------------------   Get MaxFollErr -----------------------------
PUB GetFEMax(i)
  i:= 0 #> i <# PIDMax
Return FEMax[i]

' ---------------------   Get Actual FollErr -----------------------------
PUB GetFE(i)
  i:= 0 #> i <# PIDMax
Return FE[i]
' ---------------------   Get Foll Err trip -----------------------------
PUB GetFETrip(i)
  i:= 0 #> i <# PIDMax
Return FETrip[i]

PUB GetFEAnyTrip          'Any FE trip
Return FEAny

' ---------------------   Set Ki  -----------------------------
PUB SetKI(i,lKi)
  i:= 0 #> i <# PIDMax
  KI[i]:=lKi
  
' ---------------------   Get Ki  -----------------------------
PUB GetKI(i)
  i:= 0 #> i <# PIDMax
Return KI[i]

' ---------------------   Set Kp  -----------------------------
PUB SetKp(i,lK)
  i:= 0 #> i <# PIDMax
  Kp[i]:=lK
  
' ---------------------   Get Kp  -----------------------------
PUB GetKp(i)
  i:= 0 #> i <# PIDMax
Return Kp[i]

' ---------------------   Set K   -----------------------------
PUB SetK(i,lK) ' Set K
  i:= 0 #> i <# PIDMax
  K[i]:=lK
  
' ---------------------   Get K   -----------------------------
PUB GetK(i)     'Get K
  i:= 0 #> i <# PIDMax
Return K[i]

' ---------------------   Set Acc   -----------------------------
PUB SetAcc(i,lAcc)
  i:= 0 #> i <# PIDMax
  Acc[i]:=lAcc
  
' ---------------------   Get Acc   -----------------------------
PUB GetAcc(i)
  i:= 0 #> i <# PIDMax
Return Acc[i]

' ---------------------   Set max Vel   -----------------------------
PUB SetMaxVel(i,lVel)
  i:= 0 #> i <# PIDMax
  MaxVel[i]:=lVel
  
' ---------------------   Get max Vel   -----------------------------
PUB GetMaxVel(i)
  i:= 0 #> i <# PIDMax
Return MaxVel[i]


' ---------------------   Set Position Scale factor  -----------------------------
PUB SetPosScale(i,lS)
  i:= 0 #> i <# PIDMax
  PosScale[i]:=lS
  
' ---------------------   Get PosScale -----------------------------
PUB GetPosScale(i)
  i:= 0 #> i <# PIDMax
Return PosScale[i]

' ---------------------   Set Velocity Scale factor  -----------------------------
PUB SetVelScale(i,lS)
  i:= 0 #> i <# PIDMax
  VelScale[i]:=lS
  
' ---------------------   Get  Velocity Scale factor -----------------------------
PUB GetVelScale(i)
  i:= 0 #> i <# PIDMax
Return VelScale[i]

' ---------------------   Set Output Scale factor    -----------------------------
PUB SetOutputScale(i,lS)
  i:= 0 #> i <# PIDMax
  OutputScale[i]:=lS
  
' ---------------------   Get Output Scale factor -----------------------------
PUB GetOutputScale(i)
  i:= 0 #> i <# PIDMax
Return OutputScale[i]

' ---------------------   Set Integral limiter  -----------------------------
PUB SetIlimit(i,lS)
  i:= 0 #> i <# PIDMax
  Ilimit[i]:=lS
  
' ---------------------   Get Integral limiter -----------------------------
PUB GetIlimit(i)
  i:= 0 #> i <# PIDMax
Return Ilimit[i]

' ---------------------   Return Actual Velocity Cnts/sec -----------------------------
PUB GetActVel(i)
  i:= 0 #> i <# PIDMax
Return lActVel[i]/F ' * PIDCyclesPerSec  

' ---------------------   Return Set Velocity Cnts/sec -----------------------------
PUB GetSetVel(i)
  i:= 0 #> i <# PIDMax
Return SetVel[i] ' * PIDCyclesPerSec  

' ---------------------  Return Position in cnts -----------------------------
PUB GetActPos(i)
  i:= 0 #> i <# PIDMax
Return lActPos[i]

' ---------------------  Return Raw encoder in cnts -----------------------------
PUB GetEncPos(i)
  i:= 0 #> i <# PIDMax
Return EncPos[i]

' ---------------------  Return MAE-Position in cnts -----------------------------
PUB GetMAEpos(i)
'  i:= 0 #> i <# PIDMax
Return Long[mMAEPos][0]

' ---------------------  Return MAE-Position in cnts -----------------------------
PUB GetMAEOffset(i)
'  i:= 0 #> i <# PIDMax
Return Long[mMAEOffset][0]

' ---------------------  Return actual currents -----------------------------
PUB GetActCurrent(i)
  i:= 0 #> i <# PIDMax
Return ActCurrent[i]

' ---------------------  Set Max Current -----------------------------
PUB SetMaxCurr(i,lS)
  i:= 0 #> i <# PIDMax
  MaxSetCurrent[i]:=lS

' ---------------------  Return Max allowable currents -----------------------------
PUB GetMaxSetCurrent(i)
  i:= 0 #> i <# PIDMax
Return MaxSetCurrent[i]

' ---------------------  Return Max allowable currents -----------------------------
PUB GetMaxCurrent(i)
  i:= 0 #> i <# PIDMax
Return MaxCurrent[i]

' ---------------------  Return current errorss -----------------------------
PUB GetCurrError(i)
  i:= 0 #> i <# PIDMax
Return CurrError[i]

' ---------------------  Return Ibuf -----------------------------
PUB GetIBuf(i)
  i:= 0 #> i <# PIDMax
Return lI[i]

' ---------------------  Return Delta vel -----------------------------
PUB GetDeltaVel(i)
  i:= 0 #> i <# PIDMax
Return DVT[i]

' ---------------------   Set PID mode     -----------------------------
PUB SetPIDMode(i,lMode)             '0= open loop, 1=Velocity control, 2= position control 3= Pos cntrl Vel limit
  i:= 0 #> i <# PIDMax
'  if (PIDMode[i]==0 and lMode<>0)   'Do something before closing loop to avoid sudden jumps
  PIDMode[i] := lMode

' ---------------------   Set command output in open loop mode  ------------------------
PUB SetOpenLoop(i,lOpenloopCmd)            
  i:= 0 #> i <# PIDMax
  OpenloopCmd[i] := lOpenloopCmd

' ---------------------   Kill all motors (open loop) -------------------
PUB KillAll  | i
  repeat i from 0 to PIDMax
    PIDMode[i]:=0
    
' ---------------------   Set all motors in the same PID state  -------------------
PUB SetAllPIDMode(m)  | i
  repeat i from 0 to PIDMax
    PIDMode[i]:=m

' ---------------------  Return PID Mode -----------------------------
PUB GetPIDMode(i)
  i:= 0 #> i <# PIDMax
Return PIDMode[i]

' --------------------- Return PID Time in us -----------------------------
PUB GetPIDTime
Return PIDTime/80

' --------------------- Return PIDLead Time in us -----------------------------
PUB GetPIDLeadTime
Return PIDLeadTime/80

' ---------------------  Return PID Status -----------------------------
PUB GetPIDStatus 
Return  PIDStatus

' ---------------------  Return PIDOut -----------------------------
PUB GetPIDOut(i) 
  i:= 0 #> i <# PIDMax
Return Output[i]

' ---------------------  Return Get QiK Parameter -----------------------------
PUB GetParameter(Address, Parameter)
Return GetParameter(Address, Parameter)

' ---------------------  Return Return string -----------------------------
PUB Par2Str(ParNr)
Return Par2Str(ParNr)

' ---------------------   Get PID Counter  -----------------------------
PUB GetPIDCntr
Return PIDCntr

' ---------------------   GetAnyCurrError  -----------------------------
PUB GetAnyCurrError
Return AnyCurrError

' ---------------------   Get drive Error  -----------------------------
PUB GetError(i)
  i:= 0 #> i <# PIDMax
Return Err[i]

' ---------------------   GetEncCog  -----------------------------
PUB GetEncCog
Return EncCog

' ---------------------   GetQIKCog  -----------------------------
PUB GetQIKCog
Return QIKCog

' ---------------------   GetEncCntr
PUB GetEncCntr
Return EncCntr



{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}