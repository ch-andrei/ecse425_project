--2016-03-27

library ieee;

use ieee.std_logic_1164.all; -- allows use of the std_logic_vector type
use ieee.numeric_std.all; -- allows use of the unsigned type
use STD.textio.all;

use work.memory_arbiter_lib.all;

ENTITY cpu IS
   
   GENERIC (
      File_Address_Read    : STRING    := "Init.dat";
      File_Address_Write   : STRING    := "MemCon.dat";
      Mem_Size_in_Word     : INTEGER   := 256;
      Read_Delay           : INTEGER   := 1; 
      Write_Delay          : INTEGER   := 1
   );
   PORT (
      clk                  : IN    STD_LOGIC; -- suggested: 20ns
      clk_mem              : IN    STD_LOGIC; -- must be 10 times faster than the main clock; suggested: 2ns

      reset                : IN    STD_LOGIC := '0';
      
      mem_dump             : IN    STD_LOGIC := '0';

      Asrt_flag            : out std_logic := '0'
   );
   
END cpu;

ARCHITECTURE rtl OF cpu IS

-- COMPONENTS 

COMPONENT memory IS
GENERIC 
(
    File_Address_Read   : string    := "Init.dat";
    File_Address_Read0  : string    := "Init0.dat";
    File_Address_Read1  : string    := "Init1.dat";
    File_Address_Read2  : string    := "Init2.dat";
    File_Address_Read3  : string    := "Init3.dat";
    File_Address_Write  : string    := "MemCon.dat";
    Mem_Size_in_Word    : integer   := 2048;
    Num_Bytes_in_Word   : integer   := NUM_BYTES_IN_WORD;
    Num_Bits_in_Byte    : integer   := NUM_BITS_IN_BYTE;
    Read_Delay          : integer   := 0;
    Write_Delay         : integer   := 0
);
PORT 
(
    clk         : in STD_LOGIC;
    addr        : in NATURAL;
    wordbyte    : in STD_LOGIC;
    re          : in STD_LOGIC;
    we          : in STD_LOGIC;
    dump        : in STD_LOGIC;
    dataIn      : in STD_LOGIC_VECTOR(MEM_DATA_WIDTH-1 downto 0);
    dataOut     : out STD_LOGIC_VECTOR(MEM_DATA_WIDTH-1 downto 0);
    busy        : out STD_LOGIC;
    state_o     : out STD_LOGIC_VECTOR(2 downto 0);
    wrd       : out STD_LOGIC;
    rdr       : out STD_LOGIC
);
END COMPONENT;

  -- detects if a stall must be inserted in the execution
  COMPONENT HazardDetectionControl
      PORT (
        clk             : in std_logic;
        ID_Rs           : in std_logic_vector(4 downto 0);
        ID_Rt           : in std_logic_vector(4 downto 0);
        EX_Rt           : in std_logic_vector(4 downto 0);
        ID_EX_MemRead   : in std_logic;
        BRANCH          : in std_logic;
        JUMP            : in std_logic;

        CPU_Stall       : out std_logic;
        state_o         : out integer := 0
      );
  END COMPONENT;

  -- ALU
  COMPONENT ALU
      PORT( 
        clk            : in std_logic;
        opcode         : in std_logic_vector(3 downto 0);
        data0, data1   : in std_logic_vector(31 downto 0);
        shamt          : in std_logic_vector (4 downto 0);
        data_out       : out std_logic_vector(31 downto 0);
        data_out_async : out std_logic_vector (31 downto 0); 
        HI             : out std_logic_vector (31 downto 0);
        LO             : out std_logic_vector (31 downto 0);
        zero           : out std_logic
      );
  END COMPONENT;

  -- register between IF and ID stages
  COMPONENT IF_ID
      PORT(
        clk         : in std_logic;
        inst_in     : in std_logic_vector(31 downto 0);
        addr_in     : in std_logic_vector(31 downto 0);
        IF_ID_write : in std_logic :='1'; --For hazard dectection. Always 1 unless hazard detecttion    unit changes it.
        inst_out    : out std_logic_vector(31 downto 0);
        addr_out    : out std_logic_vector(31 downto 0)
      );
  END COMPONENT;

  -- register between ID and EX stages
  COMPONENT ID_EX
    PORT(
      clk               : in std_logic;
      --Data inputs
      Addr_in           : in std_logic_vector(31 downto 0);
      RegData0_in       : in std_logic_vector(31 downto 0);
      RegData1_in       : in std_logic_vector(31 downto 0);
      SignExtended_in   : in std_logic_vector(31 downto 0);
      --Register inputs (5 bits each)
      Rs_in             : in std_logic_vector(4 downto 0);
      Rt_in             : in std_logic_vector(4 downto 0);
      Rd_in             : in std_logic_vector(4 downto 0);
       --Control inputs (8 of them?)
      RegWrite_in       : in std_logic;
      MemToReg_in       : in std_logic;
      MemWrite_in       : in std_logic;
      MemRead_in        : in std_logic;
      Branch_in         : in std_logic;
      LUI_in            : in std_logic;
      ALU_op_in         : in std_logic_vector(3 downto 0);
      ALU_src_in        : in std_logic;
      Reg_dest_in       : in std_logic;
      BNE_in            : in std_logic;
      Asrt_in           : in std_logic;
      Jal_in            : in std_logic;

      --Data Outputs
      Addr_out          : out std_logic_vector(31 downto 0);
      RegData0_out      : out std_logic_vector(31 downto 0);
      RegData1_out      : out std_logic_vector(31 downto 0);
      SignExtended_out  : out std_logic_vector(31 downto 0);
      --Register outputs
      Rs_out            : out std_logic_vector(4 downto 0);
      Rt_out            : out std_logic_vector(4 downto 0);
      Rd_out            : out std_logic_vector(4 downto 0);
      --Control outputs
      RegWrite_out      : out std_logic;
      MemToReg_out      : out std_logic;
      MemWrite_out      : out std_logic;
      MemRead_out       : out std_logic;
      Branch_out        : out std_logic;
      LUI_out           : out std_logic;
      ALU_op_out        : out std_logic_vector(3 downto 0);
      ALU_src_out       : out std_logic;
      Reg_dest_out      : out std_logic;
      BNE_out           : out std_logic;
      Asrt_out          : out std_logic;
      Jal_out           : out std_logic
    );
  END COMPONENT;

  -- register between Execution and Memory stages
  COMPONENT EX_MEM
      PORT(
        clk            : in std_logic;

        --Control Unit
        MemWrite_in    : in STD_LOGIC;
        MemRead_in     : in STD_LOGIC;
        MemtoReg_in    : in STD_LOGIC;
        RegWrite_in    : in std_logic;
        --ALU
        ALU_Result_in  : in std_logic_vector(31 downto 0);
        ALU_HI_in      : in std_logic_vector (31 downto 0);
        ALU_LO_in      : in std_logic_vector (31 downto 0);
        ALU_zero_in    : in std_logic;
        --Read Data
        Data1_in       : in std_logic_vector(31 downto 0);
        --Register
        Rd_in          : in std_logic_vector(4 downto 0);

        --Control Unit
        MemWrite_out   : out STD_LOGIC;
        MemRead_out    : out STD_LOGIC;
        MemtoReg_out   : out STD_LOGIC;
        RegWrite_out   : out std_logic;
        --ALU
        ALU_Result_out : out std_logic_vector(31 downto 0);
        ALU_HI_out     : out std_logic_vector (31 downto 0);
        ALU_LO_out     : out std_logic_vector (31 downto 0);
        ALU_zero_out   : out std_logic;
        --Read Data
        Data1_out      : out std_logic_vector(31 downto 0);
        --Register
        Rd_out         : out std_logic_vector(4 downto 0)
      );
   END COMPONENT;

  -- register between MEM and WB stages
   COMPONENT MEM_WB
      port(
        clk            : in std_logic;

        --Control Unit
        MemtoReg_in    : in std_logic;
        RegWrite_in    : in std_logic;
        --Data Memory
        busy_in        : in std_logic;
        Data_in        : in std_logic_vector(31 downto 0);
        --ALU
        ALU_Result_in  : in std_logic_vector(31 downto 0);
        ALU_HI_in      : in std_logic_vector (31 downto 0);
        ALU_LO_in      : in std_logic_vector (31 downto 0);
        ALU_zero_in    : in std_logic;
        --Register
        Rd_in          : in std_logic_vector (4 downto 0);

        --Control Unit
        MemtoReg_out   : out std_logic;
        RegWrite_out   : out std_logic;
        --Data Memory
        busy_out       : out std_logic;
        Data_out       : out std_logic_vector(31 downto 0);
        --ALU
        ALU_Result_out : out std_logic_vector(31 downto 0);
        ALU_HI_out     : out std_logic_vector (31 downto 0);
        ALU_LO_out     : out std_logic_vector (31 downto 0);
        ALU_zero_out   : out std_logic;
         --Register
        Rd_out         : out std_logic_vector (4 downto 0)
      );
   END COMPONENT;

  -- Program Counter 
  COMPONENT PC
     PORT(
       clk         : in std_logic;
       addr_in     : in std_logic_vector(31 downto 0);
       PC_write    : in std_logic := '1';
       addr_out    : out std_logic_vector(31 downto 0) := (others => '0')
     );
  END COMPONENT;

  -- Registers
  COMPONENT Registers
    PORT(
      clk            : in std_logic;
      --control
      RegWrite       : in std_logic;
      ALU_LOHI_Write : in std_logic;
      --Register file inputs
      readReg_0      : in std_logic_vector(4 downto 0);
      readReg_1      : in std_logic_vector(4 downto 0);
      writeReg       :  in std_logic_vector(4 downto 0);
      writeData      : in std_logic_vector(31 downto 0);
      ALU_LO_in      : in std_logic_vector(31 downto 0);
      ALU_HI_in      : in std_logic_vector(31 downto 0);
      --Register file outputs
      readData_0     : out std_logic_vector(31 downto 0);
      readData_1     : out std_logic_vector(31 downto 0);
      ALU_LO_out     : out std_logic_vector(31 downto 0);
      ALU_HI_out     : out std_logic_vector(31 downto 0);

      -- for testing purposes only (inspection)
      r0        : out std_logic_vector(31 downto 0);
      r1        : out std_logic_vector(31 downto 0);
      r2        : out std_logic_vector(31 downto 0);
      r3        : out std_logic_vector(31 downto 0);
      r4        : out std_logic_vector(31 downto 0);
      r5        : out std_logic_vector(31 downto 0);
      r6        : out std_logic_vector(31 downto 0);
      r7        : out std_logic_vector(31 downto 0);
      r8        : out std_logic_vector(31 downto 0);
      r9        : out std_logic_vector(31 downto 0);
      r10       : out std_logic_vector(31 downto 0);
      r11       : out std_logic_vector(31 downto 0);
      r12       : out std_logic_vector(31 downto 0);
      r13       : out std_logic_vector(31 downto 0);
      r14       : out std_logic_vector(31 downto 0);
      r15       : out std_logic_vector(31 downto 0);
      r16       : out std_logic_vector(31 downto 0);
      r17       : out std_logic_vector(31 downto 0);
      r18       : out std_logic_vector(31 downto 0);
      r19       : out std_logic_vector(31 downto 0);
      r20       : out std_logic_vector(31 downto 0);
      r21       : out std_logic_vector(31 downto 0);
      r22       : out std_logic_vector(31 downto 0);
      r23       : out std_logic_vector(31 downto 0);
      r24       : out std_logic_vector(31 downto 0);
      r25       : out std_logic_vector(31 downto 0);
      r26       : out std_logic_vector(31 downto 0);
      r27       : out std_logic_vector(31 downto 0);
      r28       : out std_logic_vector(31 downto 0);
      r29       : out std_logic_vector(31 downto 0);
      r30       : out std_logic_vector(31 downto 0);
      r31       : out std_logic_vector(31 downto 0);
      rLo       : out std_logic_vector(31 downto 0);
      rHi       : out std_logic_vector(31 downto 0)
    );
  END COMPONENT;

  -- Control Unit of the circuit is used to set the relevant control signals
  COMPONENT Control_Unit IS
      PORT(
        clk             : in std_logic;

        opCode          : in std_logic_vector(5 downto 0);
        funct           : in std_logic_vector(5 downto 0);

        --ID
        RegWrite        : out std_logic;
        --EX
        ALUSrc          : out std_logic;
        ALUOpCode       : out std_logic_vector(3 downto 0);
        RegDest         : out std_logic;
        Branch          : out std_logic;
        BNE             : out std_logic;
        Jump            : out std_logic;
        LUI             : out std_logic;
        ALU_LOHI_Write  : out std_logic;
        ALU_LOHI_Read   : out std_logic_vector(1 downto 0);

        Asrt            : out std_logic;
        Jal             : out std_logic;
        JR              : out std_logic;

        --MEM
        MemWrite        : out std_logic;
        MemRead         : out std_logic;
        --WB
        MemtoReg        : out std_logic
      );
END COMPONENT;

-- used to forward relevant signals to avoid data hazards
COMPONENT Forwarding IS
  PORT(
    EX_MEM_RegWrite : in std_logic;
    MEM_WB_RegWrite : in std_logic;
    EX_Rs     : in std_logic_vector(4 downto 0);
    EX_Rt     : in std_logic_vector(4 downto 0);
    MEM_Rd      : in std_logic_vector(4 downto 0);
    WB_Rd     : in std_logic_vector(4 downto 0);

    Forward0_EX   : out std_logic_vector(1 downto 0);
    Forward1_EX   : out std_logic_vector(1 downto 0)
    );
END COMPONENT;

COMPONENT EarlyBranching IS
  PORT(
    flush         : in std_logic;
    Branch      : in std_logic;
    EX_MEM_RegWrite : in std_logic;
    MEM_WB_RegWrite : in std_logic;
    ID_Rs     : in std_logic_vector(4 downto 0);
    ID_Rt     : in std_logic_vector(4 downto 0);
    MEM_Rd      : in std_logic_vector(4 downto 0);
    WB_Rd     : in std_logic_vector(4 downto 0);

    Forward0_Branch : out std_logic_vector(1 downto 0);
    Forward1_Branch : out std_logic_vector(1 downto 0)
    );
END COMPONENT;

COMPONENT TwoBit_Predictor IS
  PORT(
    clk             : in std_logic;
    branch          : in std_logic;
    --actual result corresponding to the last prediction that was computed
    last_pred      : in integer range 0 to 3;
    actual_taken   : in std_logic; -- 0 for not taken, 1 for taken

    branch_outcome   : out std_logic;
    pred_validate  : out integer range 0 to 3
    );
END COMPONENT;

-----------------------------------------------------
---------------DECLARATION OF SIGNALS----------------
-----------------------------------------------------

-- Registers
-- for testing purposes only (register inspection)
SIGNAL r0, r1 , r2  , r3  , r4  , r5  , r6  , r7  , r8  , r9  , r10 , r11 , r12 , r13 , r14 , r15 , 
r16 , r17 , r18 , r19 , r20 , r21 , r22 , r23 , r24 , r25 , r26 , r27 , r28 , r29 , r30 , r31 , rLo , rHi   :  std_logic_vector(31 downto 0);

-- MEMORY
signal pc_in, InstMem_address    : integer   := 0;
signal InstMem_re, inst_re_control         : std_logic := '0';
signal DataMem_addr       : integer    := 0;
signal DataMem_re         : std_logic  := '1';
signal DataMem_we         : std_logic  := '0';
signal DataMem_data, datamem_datain, datamem_dataout       : std_logic_vector (31 downto 0)  := (others => 'Z');
signal InstMem_counterVector : std_logic_vector (31 downto 0)  := (others => '0'); 
signal InstMem_busy       : std_logic  := '0';
signal DataMem_busy       : std_logic  := '0';
signal mem_data_state     : std_logic_vector(2 downto 0);
signal wrd, rdr           : std_logic;

-- PC AND memory
signal PC_addr_out : std_logic_vector(31 downto 0);
signal Imem_inst_in, Imem_addr_in, IF_ID_Imem_inst_in : std_logic_vector(31 downto 0);
signal IF_ID_inst_out, IF_ID_addr_out : std_logic_vector(31 downto 0) := (others => '0');

-- CONTROL signals
signal regWrite: std_logic;
signal ALUOpcode: std_logic_vector(3 downto 0);
signal RegDest, Branch, BNE, Jump, LUI, ALU_LOHI_Write, ALU_LOHI_Write_delayed, ALUSrc, Asrt, Jal, JR, JR_delayed : std_logic;
signal Jump_selector : std_logic_vector(1 downto 0);
signal ALU_LOHI_Read, ALU_LOHI_Read_delayed: std_logic_vector(1 downto 0);
signal MemWrite, MemRead, MemtoReg: std_logic;
signal rs, rt, rd, Imem_rs, Imem_rt, IF_ID_rt : std_logic_vector ( 4 downto 0);

--For Branch and Jump
signal Branch_taken, Branch_taken_delayed, PC_Branch, Early_Zero, Branch_Signal, BNE_Signal : std_logic;
signal Branch_addr, Branch_addr_delayed, after_Branch : std_logic_vector(31 downto 0) := (others => '0');
signal Jump_addr, Jump_addr_delayed, Jump_addr_in, pc_addr_in, after_Jump, jal_addr : std_logic_vector(31 downto 0) := (others => '0');
signal Equal : boolean;
signal JR_addr, J_addr : std_logic_vector(31 downto 0);
signal flush : std_logic;

--2-bit Counter Branch Predictor
signal last_prediction, last_prediction_in, pred_validate : integer range 0 to 3 := 0;
signal actual_taken, branch_outcome, branch_signal_in, pc_branch_in: std_logic;
signal predict_addr_upper : std_logic_vector(15 downto 0);
signal predict_addr, predict_target, predict_target_correct, predict_untaken_addr : std_logic_vector(31 downto 0);
signal branch_op, branch_select : std_logic;

--Flush signal control
signal flush_state : integer range 0 to 6 := 0;
signal re_control, we_control, data_we_control, data_re_control, reg_write_control, lohi_write_control : std_logic;

--Signals from last pipeline stage
signal ID_SignExtend, ID_EX_SignExtend, EX_SignExtend : std_logic_vector(31 downto 0);

--Hazard detection signal
signal Stall_selector : std_logic_vector (1 downto 0);
signal CPU_stall : std_logic;
signal IF_ID_regWrite,IF_ID_RegDest,IF_ID_Branch,IF_ID_BNE, ID_EX_BNE, IF_ID_Jump, ID_EX_Jump, IF_ID_MemWrite,IF_ID_MemRead,IF_ID_MemtoReg, IF_ID_Jal, IF_ID_Asrt : std_logic;
signal IF_ID_opCode, IF_ID_funct : std_logic_vector (5 downto 0);
signal IF_ID_ALUsrc : std_logic;
signal IF_ID_ALUOpcode : std_logic_vector(3 downto 0);
signal haz_instruction : std_logic_vector(31 downto 0);
signal hazard_state : integer range 0 to 7;

--Signals for Forwarding
signal Forward0_EX, Forward1_EX : std_logic_vector(1 downto 0);
signal Forward0_Branch, Forward1_Branch : std_logic_vector(1 downto 0);
signal Forward0_jump, Forward1_jump : std_logic_vector(2 downto 0);
signal Branch_data0, Branch_data1: std_logic_vector(31 downto 0);
signal Forwarding0_selector, Forwarding1_selector : std_logic_vector(2 downto 0) := "001";
signal Forwarding_enable : std_logic := '1';

--ID_EX output signals
signal ID_EX_RegRt : std_logic_vector(4 downto 0);
signal ID_EX_MemRead : std_logic;
signal ID_EX_data0_out, ID_EX_data1_out : std_logic_vector(31 downto 0);
signal ID_EX_Rs_out, ID_EX_Rt_out : std_logic_vector(4 downto 0);
signal ID_EX_addr_out : std_logic_vector(31 downto 0);
signal ID_EX_RegWrite : std_logic;
signal ID_EX_ALU_op_out : std_logic_vector(3 downto 0);
signal ID_EX_ALU_src_out : std_logic;
signal ID_EX_Branch_out : std_logic;
signal ID_EX_LUI : std_logic;
signal ID_EX_RegDest_out : std_logic;
signal ID_EX_Asrt : std_logic;
signal ID_EX_Jal, Jal_to_Reg : std_logic;
signal low_ID_EX_SignExtend: std_logic_vector(31 downto 0);
signal ID_Extend: std_logic_vector(15 downto 0);

--Signals for ALU
signal ALU_LO, ALU_HI : std_logic_vector(31 downto 0) := (others => '0');
signal data0, data1 : std_logic_vector(31 downto 0);
signal ALU_LO_out, ALU_HI_out : std_logic_vector(31 downto 0);

-- multiplexer output signals
signal ALU_data0, t_ALU_data1, ALU_data1, ALU_data_out, ALU_data_out_fast : std_logic_vector(31 downto 0);
signal EX_ALU_result : std_logic_vector(31 downto 0);
signal zero : std_logic;
signal ALU_shamt : std_logic_vector (4 downto 0);

-- EX_MEM sgianls stage to MEM_WB stage
signal ID_EX_MemWrite, EX_MEM_MemWrite : std_logic;
signal EX_MEM_MemRead : std_logic;
signal EX_MEM_RegWrite, MEM_WB_RegWrite : std_logic;
signal ID_EX_MemtoReg, EX_MEM_MemtoReg, MEM_WB_MemtoReg, MEM_WB_MemtoReg_delayed: std_logic;
signal EX_MEM_ALU_result, EX_MEM_ALU_HI, EX_MEM_ALU_LO : std_logic_vector(31 downto 0);
signal EX_MEM_ALU_zero : std_logic;
signal MEM_WB_ALU_zero, MEM_WB_busy : std_logic;
signal MEM_WB_ALU_result, MEM_WB_ALU_HI, MEM_WB_ALU_LO : std_logic_vector(31 downto 0);
signal ID_EX_Rd, EX_MEM_Rd, MEM_WB_Rd, EX_rd, Rd_W, Rd_W_in : std_logic_vector(4 downto 0);
signal EX_MEM_Data1, EX_MEM_Data_delayed, EX_MEM_data: std_logic_vector(31 downto 0);
signal MEM_WB_data, Result_W, Result_W_in: std_logic_vector(31 downto 0);

-------------------------------------------------
-----------------BEGIN BEHAVIOUR-----------------
-------------------------------------------------

BEGIN

-- Program Counter
Program_counter: PC
  PORT MAP( 
    clk         => clk,
    addr_in     => after_Jump, --should be jump_mux_out
    PC_write    => '1',-- from hazard detection
    addr_out    => PC_addr_out
  );

-- increments the pc by 4 on every clock cycle unless branch or jump signals are high
pc_increment : process (clk)
begin
  if (falling_edge(clk)) then
    if (CPU_stall /= '1' or Branch_taken = '1' or ID_EX_Jump = '1') then
      pc_in <= to_integer(unsigned(PC_addr_out)) + 4;
    else
      pc_in <= to_integer(unsigned(PC_addr_out));
    end if; 
  end if;
end process;
InstMem_counterVector <= std_logic_vector(to_unsigned(pc_in,32));
InstMem_address <= to_integer(unsigned(PC_addr_out));

-- updates read enable signal for the main instruction memory
-- (dont read when cpu is on stall)
read_instruction_mem : process (clk)
begin
  if (falling_edge(clk)) then
    if (CPU_stall /= '1' or Branch_taken = '1' or ID_EX_Jump = '1') then
      InstMem_re <= '1';
    else
      InstMem_re <= '0';
    end if;
  end if;
end process;

-- Instruction memory component
Instruction_Memory : memory
GENERIC MAP
(
    File_Address_Read   => "Init.dat",
    File_Address_Read0  => "Init0.dat",
    File_Address_Read1  => "Init1.dat",
    File_Address_Read2  => "Init2.dat",
    File_Address_Read3  => "Init3.dat",
    File_Address_Write  => "InstDump.dat",
    Mem_Size_in_Word    => 2048,
    Num_Bytes_in_Word   => 4,
    Num_Bits_in_Byte    => 8,
    Read_Delay          => 0,
    Write_Delay         => 0
)
PORT MAP
(
    clk           => clk_mem,
    addr          => InstMem_address,
    wordbyte      => '1',
    re            => inst_re_control,
    we            => '0', -- instMem never writes
    dump          => '0', -- instmem never needs to dump contents
    dataIn        => (others => '0'),
    dataOut       => Imem_inst_in,
    busy          => InstMem_busy
);

-- make sure that instruction mem is read only once per clock
inst_we_control_update : process(InstMem_re, clk)
begin
  inst_re_control <= InstMem_re;
  if (clk = '1') then
      inst_re_control <= '0';
  end if;
end process; 

Stall_selector <= (CPU_stall & Branch_taken_delayed);
-- updates currently run instruction used by further pipeline stages:
-- insert an "addi $0,$0,0" for stall or execute normal instruction
stall_or_run : process (clk)
begin
  if (falling_edge(clk)) then
    case Stall_selector is
      when "10" =>
        IF_ID_Imem_inst_in <= "00100000000000000000000000000000";
      when others =>
        IF_ID_Imem_inst_in <= Imem_inst_in;
    end case;
  end if;
end process;

-------------------------------------------------
------------------BRANCH LOGIC-------------------
-------------------------------------------------

-------------EARLY BRANCH RESOLUTION-------------

with ((IF_ID_inst_out(31 downto 26) = "000100") or (IF_ID_inst_out(31 downto 26) = "000101")) select Branch_Signal <=
  '1' when TRUE,
  '0' when others;

with (IF_ID_inst_out(31 downto 26) = "000101") select BNE_Signal <=
  '1' when TRUE,
  '0' when others;

PC_Branch <= ((Branch_Signal and (Early_Zero xor BNE_Signal)));
Branch_addr <= (ID_SignExtend(29 downto 0) & "00");

with PC_Branch select after_Branch <=
  Branch_addr when '1',
  InstMem_counterVector when others;

BRANCH_ID : EarlyBranching
  PORT MAP(
    flush           => flush,
    Branch          => Branch_Signal,
    EX_MEM_RegWrite => ID_EX_RegWrite,
    MEM_WB_RegWrite => EX_MEM_RegWrite,
    ID_Rs           => rs,
    ID_Rt           => rt,
    MEM_Rd          => EX_MEM_Rd,
    WB_Rd           => Rd_W,

    Forward0_Branch => Forward0_Branch,
    Forward1_Branch => Forward1_Branch
    );

Forward0_jump <= Forward0_Branch & Jump;
with Forward0_jump select Branch_data0 <=
  EX_ALU_result when "010",
  Result_W when "100",
  data0     when others;

Forward1_jump <= Forward1_Branch & Jump;
with Forward1_jump select Branch_data1 <=
  EX_ALU_result when "010",
  Result_W when "100",
  data1     when others;

-- early branch prediction: zero
Equal <= (Branch_data0 = Branch_data1);
with Equal select Early_Zero <=
  '1' when TRUE,
  '0' when others;

--------TWO BIT COUNTER BRANCH PREDICTOR---------

-- update last prediction
process(clk)
begin
  if (rising_edge(clk)) then
    last_prediction <= pred_validate;
    predict_untaken_addr <= after_Branch;
  end if;
end process;

process(clk_mem)
begin
  if (falling_edge(clk_mem)) then
    last_prediction_in <= last_prediction;
    pc_branch_in <= PC_Branch;
    branch_signal_in <= Branch_Signal;
  end if;
end process;

Branch_Predictor : TwoBit_Predictor
  PORT MAP(
    clk            => clk,
    last_pred      => last_prediction_in,
    actual_taken   => pc_branch_in,
    branch         => branch_signal_in,

    branch_outcome => branch_outcome,
    pred_validate  => pred_validate
  );

with ((Imem_inst_in(31 downto 26) = "000100") or (Imem_inst_in(31 downto 26) = "000101")) select branch_op <=
  '1' when TRUE,
  '0' when others;

predict_addr_upper <= (others => Imem_inst_in(15));

with branch_op select predict_addr <=
  (predict_addr_upper(13 downto 0) & Imem_inst_in(15 downto 0) & "00") when '1',
  InstMem_counterVector when others;

with (branch_op = '1' and branch_outcome = '1') select predict_target <=
  predict_addr when TRUE,
  predict_untaken_addr when others;

with PC_Branch select predict_target_correct <=
  after_Branch when '1',
  predict_target when others;

branch_select <= branch_op or Branch_Signal;

process (clk)
begin
  if (falling_edge(clk)) then
    case branch_select is
      when '1' =>
        pc_addr_in <= predict_target_correct;
      when '0' =>
        pc_addr_in <= after_Jump;
      when others => null;
    end case;
  end if;
end process;

-------------------------------------------------
--------------------JUMP LOGIC-------------------
-------------------------------------------------

-- get correct jump address (different for jr and j instructions)
JR_addr <= (ALU_data0(29 downto 0) & "00");
J_addr <= "0000" & IF_ID_inst_out(25 downto 0) & "00";
with JR select Jump_addr <=
  JR_addr when '1',
  J_addr when others;

-- select correct after jump address (JR address is ready 1 cycle later so it need not be delayed)
Jump_selector <= Jump & JR;
with Jump_selector select Jump_addr_in <=
  Jump_addr when "11",
  Jump_addr_delayed when others;

-- if Jump control is on, then get the jump address for PC
with Jump select after_Jump <=
  Jump_addr_in when '1',
  after_Branch when others;

-- selects destination register depending on instruction format
with RegDest select EX_rd <=
  ID_EX_Rd when '1',
  ID_EX_Rt_out when others;

with Jal_to_Reg select Rd_W_in <=
  "11111" when '1',
  Rd_W when others;

with Jal_to_Reg select Result_W_in <=
  jal_addr when '1',
  Result_W when others;

-----------------------
------DATA MEMORY------ 
-----------------------
Data_Memory : memory
GENERIC MAP
(
    File_Address_Read   => "InitData.dat",
    File_Address_Read0  => "Init4.dat",
    File_Address_Read1  => "Init5.dat",
    File_Address_Read2  => "Init6.dat",
    File_Address_Read3  => "Init7.dat",
    File_Address_Write  => "DataDump.dat",
    Mem_Size_in_Word    => 2048,
    Num_Bytes_in_Word   => 4,
    Num_Bits_in_Byte    => 8,
    Read_Delay          => 0,
    Write_Delay         => 0
)
PORT MAP
(
    clk           => clk_mem,
    addr          => DataMem_addr, 
    wordbyte      => '1',
    re            => data_re_control,
    we            => data_we_control,
    dump          => mem_dump,
    dataIn        => datamem_datain,
    dataOut       => datamem_dataout,
    busy          => DataMem_busy,
    state_o       => mem_data_state,
    wrd           => wrd,
    rdr           => rdr
);
datamem_datain <= EX_MEM_Data_delayed;
DataMem_data <= datamem_dataout;
-- get address for data memory (must multiply by 4 or shift left by 2)
DataMem_addr <= to_integer(unsigned(EX_MEM_data (29 downto 0) & "00"));

-- make sure that data mem is read only once per clock
data_we_control_update : process(we_control, re_control, clk)
begin
  data_we_control <= we_control;
  data_re_control <= re_control;
  if (falling_edge(clk)) then
      data_we_control <= '0';
      data_re_control <= '0';
  end if;
end process; 


-- Control circuit of the pipeline
Control: Control_Unit
  PORT MAP(
    -- inputs
    clk       => clk,
    opCode    => IF_ID_opCode,
    funct     => IF_ID_funct,

    -- outputs
    --ID (Registers)
    RegWrite  => regWrite,

    --EX
    ALUOpCode       => ALUOpcode,
    RegDest         => RegDest,
    Branch          => Branch,
    ALUSrc          => ALUSrc,
    BNE             => BNE,
    Jump            => Jump,
    LUI             => LUI,
    ALU_LOHI_Write  => ALU_LOHI_Write,
    ALU_LOHI_Read   => ALU_LOHI_Read,
    Asrt            => Asrt,
    Jal             => Jal,
    JR              => JR,
    --MEM (data mem)
    MemWrite        => MemWrite,
    MemRead         => MemRead,
    --WB
    MemtoReg        => MemtoReg
    );

-- Component representing the registers of the CPU
Register_bank: Registers
  PORT MAP(
    clk     => clk,

    RegWrite  => reg_write_control,
    ALU_LOHI_Write  => lohi_write_control,

    readReg_0   => rs,
    readReg_1   => rt,
    writeReg    => Rd_W_in,
    writeData   => Result_W_in,

    ALU_LO_in   => ALU_LO,
    ALU_HI_in   => ALU_HI,

    readData_0  => data0,
    readData_1  => data1,

    ALU_LO_out  => ALU_LO_out,
    ALU_HI_out  => ALU_HI_out,

    -- used for inspection only (testing purposes)
    r0              => r0 ,
    r1              => r1 ,
    r2              => r2 ,
    r3              => r3 ,
    r4              => r4 ,
    r5              => r5 ,
    r6              => r6 ,
    r7              => r7 ,
    r8              => r8 ,
    r9              => r9 ,
    r10             => r10,
    r11             => r11,
    r12             => r12,
    r13             => r13,
    r14             => r14,
    r15             => r15,
    r16             => r16,
    r17             => r17,
    r18             => r18,
    r19             => r19,
    r20             => r20,
    r21             => r21,
    r22             => r22,
    r23             => r23,
    r24             => r24,
    r25             => r25,
    r26             => r26,
    r27             => r27,
    r28             => r28,
    r29             => r29,
    r30             => r30,
    r31             => r31,
    rLo             => rLo,
    rHi             => rHi
    );

-------------------------------------------------
-------------------FLUSH LOGIC-------------------
-------------------------------------------------

-- flushing means to prevent any operation that entered the pipeline after branch/jump instruction
-- from writing to registers/memory if branch is taken or jump is performed

with flush_state select re_control <= 
  DataMem_re when 0,
  DataMem_re when 4,
  DataMem_re when 6,
  '0' when others;

with flush_state select we_control <=
  DataMem_we when 0,
  DataMem_we when 4,
  DataMem_we when 6,
  '0' when others;

with flush_state select reg_write_control <= 
  MEM_WB_RegWrite when 0,
  MEM_WB_RegWrite when 4,
  MEM_WB_RegWrite when 6,
  '0' when others;

with flush_state select lohi_write_control <=
  ALU_LOHI_Write_delayed when 0,
  ALU_LOHI_Write_delayed when 4,
  ALU_LOHI_Write_delayed when 6,
  '0' when others;

with flush_state select flush <=
  '0' when 0,
  '0' when 4,
  '0' when 6,
  '1' when others;

-- 7 state final state machine for pipeline flush (need to flush for up to 5 clock cycles)
flush_fsm : process (clk)
begin
  if (rising_edge(clk)) then 
    case flush_state is
      -- jump and branch states
      when 0 =>
        Forwarding_enable <= '1';
        if ((Branch_taken = '1' and Branch = '1')) then
          Forwarding_enable <= '0';
          flush_state <= 4;
        elsif (Jump = '1') then
          Forwarding_enable <= '0';
          flush_state <= 6;
          if (Jal = '1') then 
            -- update jump address for jal
            jal_addr <=  std_logic_vector(to_unsigned(to_integer(unsigned(PC_addr_out)) - 8, 32));
          end if;
        end if; 
      when 1 =>
        flush_state <= 0;
        Forwarding_enable <= '1';
      when 2 =>
        flush_state <= 1;

      when 3 =>
        flush_state <= 2;

      -- branch specific state 4
      -- flush is disabled in state 4 to allow for completion of the instruction immediately before branch
      when 4 =>
        flush_state <= 3;

      -- jump specific states 5,6
      when 5 =>
        flush_state <= 3;
      -- flush is disabled in state 6 to allow for completion of the instruction immediately before jump
      when 6 =>
        flush_state <= 5;
        if (ID_EX_Jal = '1') then
          -- disable flush, to allow for writing to register 31
          flush_state <= 4;
        end if;
      when others =>
        flush_state <= 0;
    end case;
  end if;
end process;

-- delays multiple signals for synchronization purposes:
-- acts as a pipeline register but is used by signals from different pipeline stages
delay_buffer : process (clk)
begin
  if (rising_edge(clk)) then
    haz_instruction <= IF_ID_Imem_inst_in;
    Jump_addr_delayed <= Jump_addr;
    Branch_addr_delayed <= Branch_addr;
    MEM_WB_MemtoReg_delayed <= MEM_WB_MemtoReg;
    EX_MEM_Data_delayed <= EX_MEM_Data1;
    Rd_W <= MEM_WB_Rd;
    Jal_to_Reg <= ID_EX_Jal;
    ID_EX_Jump <= IF_ID_Jump;
    Branch_taken <= PC_Branch;
    ALU_LOHI_Write_delayed <= ALU_LOHI_Write;
    ALU_LOHI_Read_delayed <= ALU_LOHI_Read;
    JR_delayed <= JR;
    Branch_taken_delayed <= Branch_taken;
  end if;
end process;

-- pipeline register
-- IF_ID stage
IF_ID_stage: IF_ID
  PORT MAP(
    clk           => clk,
    inst_in       => IF_ID_Imem_inst_in,
    addr_in       => PC_addr_out,
    IF_ID_write   => '1',
    inst_out      => IF_ID_inst_out,
    addr_out      => IF_ID_addr_out
    );

-- decompose the read instruction into subsignals
IF_ID_opCode <= IF_ID_inst_out(31 downto 26);
IF_ID_funct <= IF_ID_inst_out(5 downto 0);
rs <= IF_ID_inst_out(25 downto 21);
rt <= IF_ID_inst_out(20 downto 16);
rd <= IF_ID_inst_out(15 downto 11);

----------------------------------
-- MFLO and MFHI LOGIC
----------------------------------
with ALU_LOHI_Read_delayed select EX_ALU_result <=
  ALU_LO_out when "01",
  ALU_HI_out when "10",
  ALU_data_out when others;

--------------------------------
-- Sign Extend
--------------------------------
ID_Extend <= (others => IF_ID_inst_out(15));
ID_SignExtend <= (ID_Extend & IF_ID_inst_out(15 downto 0));

Imem_rs <= IF_ID_Imem_inst_in(25 downto 21);
Imem_rt <= IF_ID_Imem_inst_in(20 downto 16);
IF_ID_rt <= rt;

-- Hazard detection
Hazard : HazardDetectionControl
  PORT MAP (
    clk             => clk,
    EX_Rt           => IF_ID_rt,
    ID_Rs           => Imem_rs,
    ID_Rt           => Imem_rt,
    ID_EX_MemRead   => MemRead,
    BRANCH          => Branch,
    JUMP            => Jump,

    CPU_Stall       => CPU_stall,
    state_o         => hazard_state
  );

-- renaming signals
IF_ID_regWrite       <=     regWrite;
IF_ID_RegDest        <=     RegDest;
IF_ID_Branch         <=     Branch;
IF_ID_BNE            <=     BNE;
IF_ID_Jump           <=     Jump;
IF_ID_Asrt           <=     Asrt;
IF_ID_Jal            <=     Jal;
IF_ID_MemWrite       <=     MemWrite;
IF_ID_MemRead        <=     MemRead;
IF_ID_MemtoReg       <=     MemtoReg;
IF_ID_ALUsrc         <=     ALUSrc;
IF_ID_ALUOpcode      <=     ALUOpcode;

-- ID_EX stage register
ID_EX_stage: ID_EX
  PORT MAP(
    clk               => clk,

    --Data inputs
    Addr_in           => IF_ID_addr_out,
    RegData0_in       => data0,
    RegData1_in       => data1,
    SignExtended_in   => ID_SignExtend,

    --Register inputs (5 bits each)
    Rs_in             => rs,
    Rt_in             => rt,
    Rd_in             => rd,

    --Control inputs (8 of them?)
    RegWrite_in       => IF_ID_regWrite,
    MemToReg_in       => IF_ID_MemtoReg,
    MemWrite_in       => IF_ID_MemWrite,
    MemRead_in        => IF_ID_MemRead,
    Branch_in         => IF_ID_Branch,
    LUI_in            => LUI,
    ALU_op_in         => IF_ID_ALUOpcode,
    ALU_src_in        => IF_ID_ALUsrc,
    Reg_dest_in       => IF_ID_RegDest,
    BNE_in            => IF_ID_BNE,
    Asrt_in           => IF_ID_Asrt,
    Jal_in            => IF_ID_Jal,

    --Data Outputs
    Addr_out          => ID_EX_addr_out,
    RegData0_out      => ID_EX_data0_out,
    RegData1_out      => ID_EX_data1_out,
    SignExtended_out  => ID_EX_SignExtend,
    --Register outputs
    Rs_out            => ID_EX_Rs_out,
    Rt_out            => ID_EX_Rt_out,
    Rd_out            => ID_EX_Rd,
    --Control outputs
    RegWrite_out      => ID_EX_RegWrite,
    MemToReg_out      => ID_EX_MemtoReg,
    MemWrite_out      => ID_EX_MemWrite,
    MemRead_out       => ID_EX_MemRead,
    Branch_out        => ID_EX_Branch_out,
    LUI_out           => ID_EX_LUI,
    ALU_op_out        => ID_EX_ALU_op_out,
    ALU_src_out       => ID_EX_ALU_src_out,
    Reg_dest_out      => ID_EX_RegDest_out,
    BNE_out           => ID_EX_BNE,
    Asrt_out          => ID_EX_Asrt,
    Jal_out           => ID_EX_Jal
  );

-- selects LUI signal
with LUI select EX_SignExtend <=
  ID_EX_SignExtend when '0',
  low_ID_EX_SignExtend when '1',
  (others => 'Z') when others;

-- sign extend
low_ID_EX_SignExtend <= ID_EX_SignExtend(15 downto 0) & "0000000000000000";

----------------------------------
---------Forwarding Logic---------
----------------------------------

Forwarding_unit: Forwarding
  PORT MAP(
    EX_MEM_RegWrite => ID_EX_RegWrite,
    MEM_WB_RegWrite => EX_MEM_RegWrite,
    EX_Rs           => ID_EX_Rs_out,
    EX_Rt           => ID_EX_Rt_out,
    MEM_Rd          => EX_MEM_Rd,
    WB_Rd           => Rd_W,

    Forward0_EX     => Forward0_EX,
    Forward1_EX     => Forward1_EX
  );

Forwarding0_selector <= (Forward0_EX & Forwarding_enable);
Forwarding1_selector <= (Forward1_EX & Forwarding_enable);

-- select DATA0 input for main ALU
with Forwarding0_selector select ALU_data0 <=
  EX_ALU_result when "011",
  Result_W when "101",
  ID_EX_data0_out when others;

-- select DATA1 input for main ALU
with Forwarding1_selector select t_ALU_data1 <=
  EX_ALU_result when "011",
  Result_W when "101",
  ID_EX_data1_out when others;

-- immediate value or data2 for main ALU data1 input
with ALUSrc select ALU_data1 <=
  EX_SignExtend when '1',
  t_ALU_data1 when others;

------------------------------
------main ALU component------
------------------------------
main_ALU: ALU
  PORT MAP(
    clk       => clk,
    opcode    => ALUOpcode,
    data0     => ALU_data0,
    data1     => ALU_data1,
    shamt     => ALU_shamt,
    data_out  => ALU_data_out,
    data_out_async => ALU_data_out_fast,
    HI        => ALU_HI,
    LO        => ALU_LO,
    zero      => zero
  );
ALU_shamt <= EX_SignExtend(10 downto 6);

-- EX_MEM stage
EX_MEM_stage: EX_MEM
  PORT MAP(
    clk            => clk,

    --Control Unit
    MemWrite_in    => ID_EX_MemWrite,
    MemRead_in     => ID_EX_MemRead,
    MemtoReg_in    => ID_EX_MemtoReg,
    RegWrite_in    => ID_EX_RegWrite,
    --ALU
    ALU_Result_in  => EX_ALU_result,
    ALU_HI_in      => ALU_HI,
    ALU_LO_in      => ALU_LO,
    ALU_zero_in    => zero,
    --Read Data
    Data1_in       => t_ALU_data1,
    --Register
    Rd_in          => EX_rd,

    --Control Unit
    MemWrite_out   => DataMem_we,
    MemRead_out    => DataMem_re,
    MemtoReg_out   => EX_MEM_MemtoReg,
    RegWrite_out   => EX_MEM_RegWrite,
    --ALU
    ALU_Result_out => EX_MEM_data,
    ALU_HI_out     => EX_MEM_ALU_HI,
    ALU_LO_out     => EX_MEM_ALU_LO,
    ALU_zero_out   => EX_MEM_ALU_zero,
    --Read Data
    Data1_out      => EX_MEM_Data1,
    --Register
    Rd_out         => EX_MEM_Rd
  );

-- MEM_WB stage register
MEM_WB_stage: MEM_WB
  PORT MAP(
    clk            => clk,
    --Control Unit
    MemtoReg_in    => EX_MEM_MemtoReg,
    RegWrite_in    => EX_MEM_RegWrite,
    --Data Memory
    busy_in        => DataMem_busy,
    Data_in        => DataMem_data,
    --ALU
    ALU_Result_in  => EX_MEM_data,
    ALU_HI_in      => EX_MEM_ALU_HI,
    ALU_LO_in      => EX_MEM_ALU_LO,
    ALU_zero_in    => EX_MEM_ALU_zero,
    --Register
    Rd_in          => EX_MEM_Rd,
    --Control Unit
    MemtoReg_out   => MEM_WB_MemtoReg,
    RegWrite_out   => MEM_WB_RegWrite,
    --Data Memory
    busy_out       => MEM_WB_busy,
    Data_out       => MEM_WB_data,
    --ALU
    ALU_Result_out => MEM_WB_ALU_result,
    ALU_HI_out     => MEM_WB_ALU_HI,
    ALU_LO_out     => MEM_WB_ALU_LO,
    ALU_zero_out   => MEM_WB_ALU_zero,
    --Register
    Rd_out         => MEM_WB_Rd
  );

with MEM_WB_MemtoReg select Result_W <=
  DataMem_data when '1',
  MEM_WB_ALU_result when others;

END rtl;
