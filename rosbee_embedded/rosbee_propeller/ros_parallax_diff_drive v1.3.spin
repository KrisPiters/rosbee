{{
  Entry point for the Rosbee II Parallax control board.

  This is the cog which communicates with the on board notebook with ROS, using the standard protocol for serial communication.
  See http://lectoraatmechatronica.wikispaces.com/file/view/Serieel%20protocol%20voor%20robotica%20r1.2.pdf/381442566/Serieel%20protocol%20voor%20robotica%20r1.2.pdf
  (in Dutch, will be translated soon)
  This implementation uses a subset of available commands of the protocol. The messages implemented are:
  '$0\r' -> halt robot
  '$1\r' -> start robot
  '$2,vx,rot\r', ie '$2,100,-100\r' -> Turn / move robot with specified values vx and rot.

  vx is the forward velocity, in mm/s.
  rot is the rotational speed in mrad/s.

  This implementation should echo the current values using the same protocol (to be implemented).

  Heartbeat / watchdog timer: tbd.

  Reversions:
  0.1: DV - basic implementation, without watchdog or command echos.
  1.0; sept 2015 KP/HK Encoder counts modifid for 1:50 motor 1444
  1.2; sept HK Separate cog for velocity calculations
  1.3; sept KP Made corrections for wheel directions

  License: MIT (see included LICENSE file) 


}}
CON
  ' clock settings
  _clkmode=xtal1+pll16x
  _xinfreq = 5000000 
        
  Led = 27

  'Time related Constants
  CLK_FREQ = ((_clkmode-xtal1)>>6)*_xinfreq
  MS_001 = CLK_FREQ / 1_000
  US_001 = CLK_FREQ / 1
          
  'PID constants
  nPIDLoops = 2
  MotorCnt = nPIDLoops
  MotorIndex = MotorCnt - 1

  'Quadrature encoders
  Enc0Pin  = 0            'Start pin
  EncCnt   = 2            'Number of encoders

  'PIDCTime = 10           ' PID Cycle time ms

  'Serial pins QiK
  TXQ      = 25           ' Serial out to QiC
  RXQ      = 26           ' Serial in

  'Serial port 
  CR = 13                      
  LF = 10
  CE = 11                 'CE: Clear to End of line
  TXD = 30
  RXD = 31
  Baud = 115200 '256000 '115200 '250000 '1000000 '115200 '230400 '115200

  'Misc characters
  ST = 36 'dollar sign
  SEP = 44 'comma, used to seperate command params.
  MINUS = 45 'minus
  DOT = 46 'dot

  SERIAL_MESSAGE_MAX_LENGTH = 64

  PIDCTIME = 10.0                  ' PID Cycle time ms
  WHEEL_BASE_WIDTH = 0.328         ' 0.332
  COUNTS_PER_ROTATION = 3200.0     ' 1440.0 '3200.0
  WHEEL_CIRCUMFERENCE = 123.0 * PI ' MM
  
  COUNTS_PER_MM = COUNTS_PER_ROTATION / WHEEL_CIRCUMFERENCE
  MM_PER_COUNT = WHEEL_CIRCUMFERENCE / COUNTS_PER_ROTATION
  
  'Factor used to convert the Velocity of Each Wheel (in mm/s) to Counts/PID Cycle
  'Example 2000 counts per rotation | PIDTIME 10 ms | Circumference 1000 mm
  '>>> 20 counts per PID Cycle when the wheel is traveling at 1000mm/s
  '>>> The Setpoint for this wheel will be set to 20  
  CONVERSIONFACTOR = (WHEEL_CIRCUMFERENCE / (COUNTS_PER_ROTATION / (1000.0/PIDCTIME)))  
  MM_PER_S_TO_CNTS_PER_PIDCYCLE = CONVERSIONFACTOR

  RIGHTMOTOR = 1                'change this to redefine front (x-axis) of robot
  LEFTMOTOR = 0                 'change this to redefine front (x-axis) of robot  

  'Leave DEBUG set to 0 when using with ROS!
  DEBUG = 0                     'Debug flag.
  
  
OBJ
  t             : "Timing"
  PID           : "PID Connect V5_4"                    ' PID contr. 4 loops. for wheels
  num           : "simple_numbers"                      ' Number to string conversion
  serial        : "FullDuplexSerial_rr005"              ' PC command and debug interface
  STRs          : "STRINGS2hk"
  F32           : "F32"                                 ' float32 support 

VAR 
  Byte SerialCog ' Cog for serial communication
  Byte SerialMSG[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the incoming string
  Byte SerialMSGOUT[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the outgoing string
  Byte ParserBuffer[SERIAL_MESSAGE_MAX_LENGTH] ' Buffer for the parser
  Byte p ' Pointer to a position in the incoming string buffer
  Long error 'Error value, error is filled if there are problems with reading / parsing the message. If the error = 0,
             'was parsed succesfully.          
  
  Byte PIDCog 'Cog for the PID control system
  Byte QiKCog 'Cog for the QIK motor drivers
  Byte F32cog ''cog for floating point calculations
    
  Long RobotEnabled   'Boolean variable to store actual enable/disabled status of the robot
  Long Setp[MotorCnt] 'Shared with the PID cog, contais the setpoint for each motor.
  Long setpL, setpR   'Private Global variables to store calculated setpoints before setting them
  Long vx, rot        'Variables to store received forward and rotational velocities from ROS 

  Long enco[MotorCnt] 'stores the current motor count
    
  Long actVelMMS  'Long used to store actual speed in mm/s for feedback over serial
  Long actVelRadS 'Long used to store actual rotation speed in mrad/s for feedback over serial 
  Long actPosMMS  'Long used for the absolute average position of platform
  Long maincnt 'Long to store main loopcnt
  
PUB main
  {{
    Entry point for this system. Starts the serial, PID and floating point cogs.

    This method will continuously call handleSerial 
    Parameters:
      none
    Returns: none and never.

  }} 

  init

  'serial.
        
  repeat
    'if serial.rxavail == true
      receiveSerial
    'calculateSetpoints
    'setSetpoints
    'calculateCurrentVelocity
    'sendSerial(2)

PRI printDebug



PRI init  | PIDTime
  {{
    This function starts the Serial, Float and PID Cogs.
    Sets the PID parameters.
    Sets the PID Mode to velocity control.
    Sets the used global variables to default values.

    Parameters:
      
    Returns: none
    
  }}

  
  
  SerialCog:=Serial.Start(RXD, TXD, 0, Baud)

  F32cog  := F32.Start

  PIDTime := F32.fround(PIDCTIME)
  PIDCog  := PID.Start(PIDTime, @Setp,  Enc0Pin, EncCnt, TxQ, RxQ, nPIDLoops)
  
  repeat while PID.GetPIDStatus<>2                      'Wait while PID initializes

  PID.SetAllPIDMode(1)
  setPIDPars

  T.Pause1s(5)                                            'Wait a few seconds for the powersupply to stabilize.
  
  haltRobot

  if(DEBUG) '<--------------------------------------------------'<-------------------------------------------------- 
      serial.str(string("CONVERSIONFACTOR:"))
      serial.dec(f32.FTrunc(CONVERSIONFACTOR))
      serial.tx(CR) 
      serial.tx(LF)  

PRI receiveSerial | val, i, j, messageComplete
  {{
    Reads the serial message transmitted and parses this message.
    Depending on the message, this function will call 'move' to move the platform.

    This also sends back the appropriate message according to the protocol. 

    Parameters: none

    Returns: none

    Modifies:
      error: (2<<1) will be added to error if the message buffer is full and no termination char was found

     If DEBUG is set, this will also send debug information to the serial terminal.
    
    Todo:
      Add a proper return message for the '2' type with current speeds.
      Add support for error transmission back to the control computer.
      Check if the wordfill works correctly.
  }}

  Serial.rxFlush
  
  bytefill(@SerialMSG,0,SERIAL_MESSAGE_MAX_LENGTH) ''empty SerialMSG     
  
  i := 0                        'iterator counter for filling SerialMSG
  j := 0                        'iterator for sending back the contents of SerialMSG
  error:=0                      'resets the error value to 0, as this is a new serial message 
  messageComplete := false
  
  repeat until serial.rx == ST  'Busy wait until a '$' has been received
  repeat until messageComplete  'Busy wait until a termination char has received or an error has occurred   
    val := serial.rx
    if (val == CR)
      messageComplete := true
      error := 0
    if(i == SERIAL_MESSAGE_MAX_LENGTH and not messageComplete)' message buffer full and no termination char found.
      messageComplete := true
      error |= (2 << 0)
    SerialMSG[i] := val
    
    i++
            
  if(error == 0)
    case SerialMSG[0]           '0 is the first character after the '$' in the message.
      "0":                      'halt robot
        haltRobot
        sendSerial(0)          
        
      "1":                      
        enableRobot             'start robot
        sendSerial(1)
                                
      "2":                      'get velocities from ROS and send current velocities in return
        if !RobotEnabled        'If robot not yet enabled, do it now
          enableRobot
        parseParam
        calculateSetpoints
        setSetpoints
        calculateCurrentVelocity
        sendSerial(2)               
     
      "3":                      'send debug - Not Implemented
        calculateCurrentVelocity
        sendSerial(3)

      other:
        haltRobot
        
  else
    serial.str(string("Error with errno: "))
    serial.dec(error)
    serial.tx(CR) 
    serial.tx(LF)
         
PRI parseParam | vx_,vy_,rot_
  {{
    Parses the parameters from the serial message.
    The rotational and vertical velocity are sent to the move method for to move the platform

    Parameters: none
    Returns: none

    Modifies:
      p: the pointer within the parser
      error: adds a value if an error is found while parsing.

    Todo:
      Move 'p' as a global variable to within this function and pass it to parseNumber.      
  }}
  vx_  := 0
  vy_  := 0
  rot_ := 0
  p    := 1  'pointer within the parser. The first (=0) character is the type of the message and has already been used by handleSerial.
          'The second (=1) char is the beginning of the message left to parse.  
  if(serialMSG[p] == SEP)
    p++
    vx_ := parseNumber(SEP)
    if(serialMSG[p] == SEP)
      p++
      vy_ := parseNumber(SEP)
      if(serialMSG[p] == SEP)
        p++
        rot_ := parseNumber(CR)
      else
        error |= (2 << 1)      
    else
      error |= (2<<2)
  else
    error|= (2 << 3)

  if(error == 0)     
    vx  := vx_
    rot := rot_


  else
    haltRobot
    if(DEBUG) '<--------------------------------------------------'<-------------------------------------------------- 
      serial.str(string("Error encountered, halting..."))
      serial.str(string("Errno: "))
      serial.dec(error)
      serial.tx(CR) 
      serial.tx(LF)     

PRI parseNumber(term) : value | n, i, done, hasError
  {{
    Parses a number from the serialMSG, starting at index 'p' until the 'term' char has been found.
    Also stops parsing if the SERIAL_MAX_MESSAGE_LENGTH has been found

    Parameters:
      term: the termination char to end this number (ie. ',' or 'CR')
    Returns:
      value: the number of the parsed value
    Modifies:
      error: if an error occurd while parsing, the error value will be increased.
      p: the pointer will be increased until 'p' is at the same index as the 'term' char or in between if an error occurred. 
  }}
  value    := 0 ''return value
  i        := 0 ''pointer for internal array
  done     := false
  hasError := false
  
  bytefill(@ParserBuffer,0,SERIAL_MESSAGE_MAX_LENGTH)
  
  repeat until done
    if (serialMSG[p] == term or serialMSG[p] == 0)
      done := true
    if (p == SERIAL_MESSAGE_MAX_LENGTH and not done)
      done := true
      hasError := true
      error |= (2<<4)
    if(not done)
      ParserBuffer[i] := serialMSG[p]
      i++
      p++
    

  if(not hasError)
    parserbuffer[++i] := 0  
    value := serial.strToDec(@ParserBuffer)   

  if(DEBUG)   '<--------------------------------------------------'<--------------------------------------------------
    serial.str(string("Value: "))
    serial.dec(value)
    serial.tx(CR) 
    serial.tx(LF)    
  return value  

PRI sendSerial (type)

  case type
    0:
      Serial.str(string("$0 "))
    1:
      Serial.str(string("$1 "))
    2:
      Serial.str(string("$2,"))
      Serial.dec(actvelMMS)       'Platform velocity in mm/s
      Serial.str(string(",0,"))   
      Serial.dec(actvelRADS)      'Platform rotation in rad/s   
    3:
      Serial.str(string("$3,"))  'Send general info back to host
      Serial.str(string(","))
      serial.dec(f32.FTrunc(CONVERSIONFACTOR)) 'Wheel conversion factor
      Serial.str(string(","))
      Serial.dec(PID.GetActVel(RIGHTMOTOR)) 'actual motor velocity right in encoder counts / 10 ms
      Serial.str(string(","))
      Serial.dec(-PID.GetActVel(LEFTMOTOR)) 'actual motor velocity left in encoder counts / 10 ms    
      Serial.str(string(","))
      Serial.dec(actvelMMS)         'Platform velocity in mm/s   
      Serial.str(string(","))
      Serial.dec(actvelRADS)        'Platform rotation in rad/s 
      Serial.str(string(","))
      Serial.dec(-PID.GetEncPos(0)) 'motor position left      
      Serial.str(string(","))
      Serial.dec(PID.GetEncPos(1))   'motor position left
      Serial.str(string(","))
      Serial.dec(actPosMMS)          'Platform position in mm
      Serial.str(string(","))
      Serial.dec(||RobotEnabled)     'Robot enabled       
  Serial.tx(LF)


PRI calculateSetpoints | diff
  {{
    Calculates the Setpoint Values for each wheel based on the velocities for the whole platform stored in the Global Variables vx and rot.
    The setpoint values are stored in the Global Variables setpL (left wheel) and setpR (right Wheel)
    

      vx: vertical velocity (mm/s)
      rot: rotational velocity  (mrad/s)
    Returns: none

    Modifies:

      setpL: the setpoint is set according to the vx and rot
      setpR: the setpoint is set according to the vx and rot

    Used Formula:
        diff = rot * WHEEL_BASE/2
        left = (vx - diff)/MM_PER_S_TO_CNTS_PER_PIDCYCLE)
        right = (vx + diff)/MM_PER_S_TO_CNTS_PER_PIDCYCLE)
   
    Possible pitfall is concurrency on the setp array, where the PID cog might read one fresh value and one old value
    as there is no proper way to mark the array as synchronized / volatile without adding semaphores to this cog and the PID cog.
  }}
  
  setpL := f32.fround( f32.fdiv(f32.fsub(f32.ffloat(vx), f32.fdiv( f32.fmul(f32.ffloat(rot), WHEEL_BASE_WIDTH), 2.0 )), MM_PER_S_TO_CNTS_PER_PIDCYCLE) )
  setpR := f32.fround( f32.fdiv(f32.fadd(f32.ffloat(vx), f32.fdiv( f32.fmul(f32.ffloat(rot), WHEEL_BASE_WIDTH), 2.0 )), MM_PER_S_TO_CNTS_PER_PIDCYCLE) )

  
PRI setSetpoints
  {{
    Checks the global setpoint values for each wheel to be in a certain range.
    These values are then stored in the setpoint array (setp). This array is read by the PID Cog. 


    Possible pitfall is concurrency on the setp array, where the PID cog might read one fresh value and one old value
    as there is no proper way to mark the array as synchronized / volatile without adding semaphores to this cog and the PID cog.
  }}

  setp[RIGHTMOTOR] := -128 #> setpR <# 128  'Set and Limit setpoint to range {-128, 128}
  'if setpR < 129 and setpR > -129 ' only update setpoints if the setpoint is in R{-128, 128}     
  '  setp[0] := setpR

  setp[LEFTMOTOR] := -128 #> -setpL <# 128   'Set and Limit setpoint to range {-128, 128}

   if(DEBUG)   '<--------------------------------------------------'<--------------------------------------------------
    serial.str(string("setp[0]: "))
    serial.dec(setp[0])
    serial.tx(CR) 
    serial.tx(LF)
    serial.str(string("setp[1]: "))
    serial.dec(setp[1])
    serial.tx(CR) 
    serial.tx(LF)    
    
PRI calculateCurrentVelocity  | countL, countR, posLR
  {{
    Calculates the current velocities (forward velocity in mm/s, and rotation velocity in mrad/s) of the robot.
    Based on the amount of encoder ticks read by the PID Cog in one PID Cycle.

    
    The Calculated values are stored in the global variables actVelMMS and actVelRadS. 
    These Variables are read by the sendSerial method, were they are send back to the Notebook.

    Long actVelMMS 'Long used to store actual speed in mm/s for feedback over serial
    Long actVelRadS 'Long used to store actual rotation speed in mrad/s for feedback over serial                                     

            # distance traveled is the average of the two wheels 
            d = ( d_left + d_right ) / 2
            # this approximation works (in radians) for small angles
            th = ( d_right - d_left ) / self.base_width
            # calculate velocities
            self.dx = d / elapsed
            self.dr = th / elapsed
 
    actVelMMS  = ((countsleft+countsright)*MM_PER_S_TO_CNTS_PER_PIDCYCLE)/2
    actVelRadS = ((countsright-countsleft)*MM_PER_S_TO_CNTS_PER_PIDCYCLE)/WHEEL_BASE_WIDTH
    
  }}

  countR := PID.GetActVel(RIGHTMOTOR)
  countL := -PID.GetActVel(LEFTMOTOR)
  posLR  := (-PID.GetEncPos(0) + PID.GetEncPos(1))/ 2   'Calculate average platform traveled distance
  
  actVelMMS  := f32.fround(f32.fdiv(f32.fmul(f32.ffloat(countR+countL),MM_PER_S_TO_CNTS_PER_PIDCYCLE), 2.0))
  actVelRadS := f32.fround(f32.fdiv(f32.fmul(f32.ffloat(countR-countL),MM_PER_S_TO_CNTS_PER_PIDCYCLE), WHEEL_BASE_WIDTH))
  actPosMMS  := f32.fround(f32.fdiv(f32.fmul(f32.ffloat(posLR),MM_PER_S_TO_CNTS_PER_PIDCYCLE), 2.0))
'----------------------------- Stop robot motion and disable motors -----------------
PRI haltRobot
  RobotEnabled:=false
  vx         := 0
  rot        := 0
  setpL      := 0
  setpR      := 0
  setp[0]    := 0
  setp[1]    := 0
  actVelMMS  := 0
  actVelRadS := 0
  PID.KillAll

'------------------------------- Enable motors in velocity mode ----------------------
PRI enableRobot

  vx         := 0
  rot        := 0
  setpL      := 0
  setpR      := 0
  setp[0]    := 0
  setp[1]    := 0
  actVelMMS  := 0
  actVelRadS := 0
  PID.SetAllPIDMode(1)
  RobotEnabled:=true
  
'------------------------------ Set pid parameters at start of the program ----------------------
PRI setPIDPars
  {{
    Sets various PID parameters of the PID cog.
    Parameters: none
    Returns: none
    Modifies: none.
  }}
  'Set control parameters wheels
  PID.SetKi(0,800)
  PID.SetK(0,1000)
  PID.SetKp(0,1000)
  PID.SetIlimit(0,1000)
  PID.SetPosScale(0,1)
  PID.SetFeMax(0,200)
  PID.SetMaxCurr(0,4500)
  PID.SetInvert(0,1,1,-1)  ' #pid, position, velocity, output
  PID.SetPIDMode(0,1) 'velocity loop

  PID.SetKi(1,800)
  PID.SetK(1,1000)
  PID.SetKp(1,1000)
  PID.SetIlimit(1,1000)
  PID.SetPosScale(1,1)
  PID.SetFeMax(1,200)
  PID.SetMaxCurr(1,4500)
  PID.SetInvert(1,1,1,-1)  ' #pid, position, velocity, output     
  PID.SetPIDMode(1,1) 'velocity loop

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