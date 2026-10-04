---------------------------------------------------------------------------------
-- Irem M62 sound board, based on
-- Moon patrol sound board by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
---------------------------------------------------------------------------------
-- gen_ram.vhd  
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
---------------------------------------------------------------------------------
-- cpu68 - Version 9th Jan 2004 0.8
-- 6800/01 compatible CPU core 
-- GNU public license - December 2002 : John E. Kent
---------------------------------------------------------------------------------
-- jt5205 hardware by Jose Tejada (@topapate)
---------------------------------------------------------------------------------
-- Educational use only
-- Do not redistribute synthetized file with roms
-- Do not redistribute roms whatever the form
-- Use at your own risk
---------------------------------------------------------------------------------
-- Version 0.0 -- 24/11/2017 -- 
--    initial version
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity Sound_Board is
port(
 clock_E      : in std_logic; -- 3.58 Mhz/4
 areset       : in std_logic;
 audio_filter : in std_logic; -- 1 = model the LM358 ADPCM low-pass
 adpcm_gain   : in std_logic_vector(1 downto 0); -- 1x, 1.5x, 2x, 3x

 select_sound : in std_logic_vector(7 downto 0);
 audio_out    : out std_logic_vector(11 downto 0);
 snd_rom_addr : out std_logic_vector(15 downto 0);
 snd_rom_do   : in std_logic_vector(7 downto 0);
 snd_vma      : out std_logic;

 dbg_cpu_addr : out std_logic_vector(15 downto 0)
);
end Sound_Board;

architecture struct of Sound_Board is
  component YM2149
  port (
    CLK         : in  std_logic;
    CE          : in  std_logic;
    RESET       : in  std_logic;
    A8          : in  std_logic := '1';
    A9_L        : in  std_logic := '0';
    BDIR        : in  std_logic; -- Bus Direction (0 - read , 1 - write)
    BC          : in  std_logic; -- Bus control
    DI          : in  std_logic_vector(7 downto 0);
    DO          : out std_logic_vector(7 downto 0);
    CHANNEL_A   : out std_logic_vector(7 downto 0);
    CHANNEL_B   : out std_logic_vector(7 downto 0);
    CHANNEL_C   : out std_logic_vector(7 downto 0);

    SEL         : in  std_logic;
    MODE        : in  std_logic;

    ACTIVE      : out std_logic_vector(5 downto 0);

    IOA_in      : in  std_logic_vector(7 downto 0);
    IOA_out     : out std_logic_vector(7 downto 0);

    IOB_in      : in  std_logic_vector(7 downto 0);
    IOB_out     : out std_logic_vector(7 downto 0)
    );
  end component;

  component jt5205
  port (
    rst         : in  std_logic;
    clk         : in  std_logic;
    cen         : in  std_logic;
    sel         : in  std_logic_vector(1 downto 0); -- s pin
    din         : in  std_logic_vector(3 downto 0);
    sound       : out signed(11 downto 0);
    irq         : out std_logic;
    vclk_o      : out std_logic
    );
  end component;

 signal reset      : std_logic := '1';
 signal reset_cnt  : integer range 0 to 1000000 := 1000000;

 signal cpu_addr   : std_logic_vector(15 downto 0);
 signal cpu_di     : std_logic_vector( 7 downto 0);
 signal cpu_do     : std_logic_vector( 7 downto 0);
 signal cpu_rw     : std_logic;
 signal cpu_irq    : std_logic;
 signal cpu_nmi    : std_logic;
 signal cpu_vma    : std_logic;
 
 signal irqraz_cs : std_logic;
 signal irqraz_we : std_logic;
 
 signal wram_cs   : std_logic;
 signal wram_we   : std_logic;
 signal wram_do   : std_logic_vector( 7 downto 0);
 
 signal rom_cs    : std_logic;
 signal rom_do    : std_logic_vector( 7 downto 0);

 signal ay1_chan_a    : std_logic_vector(7 downto 0);
 signal ay1_chan_b    : std_logic_vector(7 downto 0);
 signal ay1_chan_c    : std_logic_vector(7 downto 0);
 signal ay1_do        : std_logic_vector(7 downto 0);
 signal ay1_audio     : std_logic_vector(9 downto 0);
 signal ay1_port_b_do : std_logic_vector(7 downto 0);
 
 signal ay2_chan_a    : std_logic_vector(7 downto 0);
 signal ay2_chan_b    : std_logic_vector(7 downto 0);
 signal ay2_chan_c    : std_logic_vector(7 downto 0);
 signal ay2_do        : std_logic_vector(7 downto 0);
 signal ay2_audio     : std_logic_vector(9 downto 0);

 signal ports_cs    : std_logic;
 signal ports_we    : std_logic;
  
 signal port1_bus   : std_logic_vector(7 downto 0);  
 signal port1_data  : std_logic_vector(7 downto 0);
 signal port1_ddr   : std_logic_vector(7 downto 0);
 signal port1_in    : std_logic_vector(7 downto 0);
 
 signal port2_bus   : std_logic_vector(7 downto 0);  
 signal port2_data  : std_logic_vector(7 downto 0);
 signal port2_ddr   : std_logic_vector(7 downto 0);
 signal port2_in    : std_logic_vector(7 downto 0);

 signal adpcm_ce    : std_logic;
 signal adpcm_cs    : std_logic;
 signal adpcm_0_we  : std_logic;
 signal adpcm_1_we  : std_logic;
 signal adpcm_0_di  : std_logic_vector(3 downto 0);
 signal adpcm_1_di  : std_logic_vector(3 downto 0);

 signal select_sound_r : std_logic_vector(7 downto 0);

 signal adpcm_0_out : signed(11 downto 0);
 signal adpcm_1_out : signed(11 downto 0);
 signal adpcm_vclk  : std_logic;

 signal audio       : std_logic_vector(12 downto 0);

 signal lpf_a       : signed(33 downto 0);
 signal lpf_c32     : signed(33 downto 0);
 signal lpf_c       : signed(33 downto 0);
 signal adpcm_lpf   : signed(12 downto 0);
 signal adpcm_sum   : signed(12 downto 0);
 signal adpcm_x     : signed(15 downto 0);
 signal adpcm_mix   : signed(15 downto 0);
 signal mix         : signed(15 downto 0);

begin

dbg_cpu_addr <= cpu_addr;

-- cs
wram_cs   <= '1' when cpu_addr(15 downto  7) = X"00"&'1' else '0'; -- 0080-00FF
ports_cs  <= '1' when cpu_addr(15 downto  4) = X"000"    else '0'; -- 0000-000F
-- M58 uses the M52-large map: ADPCM 0000-1FFF, irq ack 2000-3FFF. The 6803's
-- internal ports and RAM sit inside that window and never reach the bus.
adpcm_cs  <= '1' when cpu_addr(15 downto 13) = "000"
                  and ports_cs = '0' and wram_cs = '0' else '0';
irqraz_cs <= '1' when cpu_addr(15 downto 13) = "001" else '0';
rom_cs    <= '1' when cpu_addr(15 downto 14) /= "00"     else '0'; -- 4000-FFFF

-- write enables
wram_we    <= '1' when cpu_rw = '0' and wram_cs =   '1' else '0';
ports_we   <= '1' when cpu_rw = '0' and ports_cs =  '1' else '0';
adpcm_0_we <= '1' when cpu_rw = '0' and adpcm_cs =  '1' and cpu_addr(0) = '1' else '0';
adpcm_1_we <= '1' when cpu_rw = '0' and adpcm_cs =  '1' and cpu_addr(1) = '1' else '0';
irqraz_we  <= '1' when cpu_rw = '0' and irqraz_cs = '1' else '0';

-- mux cpu in data between roms/io/wram
cpu_di <=
  wram_do when wram_cs = '1' else
  port1_ddr when ports_cs = '1' and cpu_addr(3 downto 0) = X"0" else
  port2_ddr when ports_cs = '1' and cpu_addr(3 downto 0) = X"1" else
  port1_in  when ports_cs = '1' and cpu_addr(3 downto 0) = X"2" else
  port2_in  when ports_cs = '1' and cpu_addr(3 downto 0) = X"3" else
  snd_rom_do when rom_cs = '1' else X"55";

process (clock_E)
begin
  if rising_edge(clock_E) then
    reset <= '0';
    if reset_cnt /= 0 then
      reset_cnt <= reset_cnt - 1;
      reset <= '1';
    end if;
    if areset = '1' then
     reset_cnt <= 1000000;
    end if;
  end if;
end process;

-- irq to cpu
process (reset, clock_E)
begin
  if reset='1' then
    cpu_irq <= '0';
    select_sound_r(7) <= '0';
  elsif rising_edge(clock_E) then
    select_sound_r <= select_sound;
    if select_sound_r(7) = '0' then
      cpu_irq  <= '1';
    end if;
    if irqraz_we = '1' then
      cpu_irq  <= '0';
    end if;
  end if;
end process;

-- cpu nmi
cpu_nmi <= adpcm_vclk;

-- 6803 ports 1 and 2 (only)
process (reset, clock_E)
begin
	if reset='1' then
		port1_ddr  <= (others=>'0');  -- port1 set as input
		port1_data <= (others=>'0');  -- port1 data set to 0
		port2_ddr  <= ("11100000");   -- port2 bit 7 to 5 should always remain output to simulate mode data
		port2_data <= ("01000000");   -- port2 data bit 7 to 5 set to 2 (for mode 2 at start up)
	elsif rising_edge(clock_E) then
			if ports_cs = '1' and ports_we = '1' then
				if cpu_addr(3 downto 0) = X"0" then port1_ddr  <= cpu_do; end if;
				if cpu_addr(3 downto 0) = X"1" then port2_ddr  <= cpu_do and "11100000"; end if;
				if cpu_addr(3 downto 0) = X"2" then port1_data <= cpu_do; end if; 
				if cpu_addr(3 downto 0) = X"3" then port2_data <= cpu_do; end if;
			end if;
	end if;
end process;

port1_in <= (port1_bus and not(port1_ddr)) or (port1_data and port1_ddr);
port2_in <= (port2_bus and not(port2_ddr)) or (port2_data and port2_ddr);

-- port1 bus mux
port1_bus <= ay1_do when port2_data(4) = '0' else 
				 ay2_do when port2_data(3) = '0' else X"FF";

-- port2 bus
port2_bus <= X"FF";


-- latch adpcm (msm5205) data in
process (reset, clock_E)
begin
	if reset='1' then
		adpcm_0_di <= (others=>'0');
	elsif rising_edge(clock_E) then
			if adpcm_cs = '1' and adpcm_0_we = '1' then
				adpcm_0_di  <= cpu_do(3 downto 0);
			end if;
			if adpcm_cs = '1' and adpcm_1_we = '1' then
				adpcm_1_di  <= cpu_do(3 downto 0);
			end if;
	end if;
end process;

-- 384 kHz clock enable
process( reset, clock_E )
  variable CLK_SUM : integer;
begin
  if reset = '1' then
    CLK_SUM := 0;
    adpcm_ce <= '0';
  elsif rising_edge(clock_E) then
    adpcm_ce <= '0';
    CLK_SUM := CLK_SUM + 384;
    if CLK_SUM >= 895 then
      CLK_SUM := CLK_SUM - 895;
      adpcm_ce <= '1';
    end if;
  end if;
end process;

-- MSM5205 ADPCM decoder chips
adpcm_0 : jt5205
port map (
  rst   => ay1_port_b_do(0),
  clk   => clock_E,
  cen   => adpcm_ce,
  sel   => ay1_port_b_do(3 downto 2),
  din   => adpcm_0_di,
  sound => adpcm_0_out,
  irq   => open,
  vclk_o=> adpcm_vclk
  );

adpcm_1 : jt5205
port map (
  rst   => ay1_port_b_do(1),
  clk   => clock_E,
  cen   => adpcm_ce,
  sel   => ay1_port_b_do(3 downto 2),
  din   => adpcm_1_di,
  sound => adpcm_1_out,
  irq   => open,
  vclk_o=> open
  );

-- ADPCM low-pass (M52-Sound G, sheet on manual page 30). The two MSM5205
-- outputs are summed through R19/R20 and buffered by 3N-A, then pass through
-- R12/C30 and a unity-gain Sallen-Key (R13, R14, C32 0.027u, C36 0.0068u)
-- on 3N-B before joining the AY outputs at VR1. The AYs are not filtered.
-- All three resistors are 10K, C30 is 0.022u: -3dB at 620Hz, third order.
-- Simulated as the circuit itself, one forward Euler step per clock_E: the
-- states are the three capacitor voltages (13.16 fixed point) and each k is
-- dt/(10K*C) at 20 fractional bits. Matches the analog response to 0.1dB.
process( reset, clock_E )
  constant KF   : natural := 20;
  constant K_A  : signed(17 downto 0) := to_signed( 5326, 18); -- C30
  constant K_B  : signed(17 downto 0) := to_signed( 4340, 18); -- C32
  constant K_C  : signed(17 downto 0) := to_signed(17232, 18); -- C36
  variable v_in, v_b, i_a, i_b, i_c : signed(33 downto 0);
  variable prod : signed(51 downto 0);
  variable y    : signed(33 downto 0);
begin
  if reset = '1' then
    lpf_a   <= (others => '0');
    lpf_c32 <= (others => '0');
    lpf_c   <= (others => '0');
    adpcm_lpf <= (others => '0');
  elsif rising_edge(clock_E) then
    v_in := shift_left(resize(resize(adpcm_0_out, 13) + resize(adpcm_1_out, 13), 34), 16);
    v_b  := lpf_c + lpf_c32;
    i_a  := (v_in - lpf_a) - (lpf_a - v_b);
    i_b  := (lpf_a - v_b) - (v_b - lpf_c);
    i_c  := v_b - lpf_c;
    prod := i_a * K_A; lpf_a   <= lpf_a   + resize(shift_right(prod, KF), 34);
    prod := i_b * K_B; lpf_c32 <= lpf_c32 + resize(shift_right(prod, KF), 34);
    prod := i_c * K_C; lpf_c   <= lpf_c   + resize(shift_right(prod, KF), 34);
    -- a step overshoots by a couple of LSBs; clamp to the 13-bit sum's range
    y := shift_right(lpf_c, 16);
    if y > 4095 then
      adpcm_lpf <= to_signed(4095, 13);
    elsif y < -4096 then
      adpcm_lpf <= to_signed(-4096, 13);
    else
      adpcm_lpf <= resize(y, 13);
    end if;
  end if;
end process;

adpcm_sum <= adpcm_lpf when audio_filter = '1' else
             resize(adpcm_0_out, 13) + resize(adpcm_1_out, 13);

-- ADPCM level against the AYs. The board feeds VR1 through R15 2.2K (read
-- from a photo) against R25 10K for the AYs, so it mixes the samples hotter
-- than MAME's flat routing; the exact factor is set by ear (OSD).
adpcm_x <= resize(adpcm_sum, 16);
with adpcm_gain select adpcm_mix <=
  adpcm_x + shift_right(adpcm_x, 1) when "01", -- 1.5x
  shift_left(adpcm_x, 1)            when "10", -- 2x
  shift_left(adpcm_x, 1) + adpcm_x  when "11", -- 3x
  adpcm_x                           when others; -- 1x

-- audio mux: the AYs are unipolar, the ADPCM sum is signed and offset by 4096
-- (the two separate 2048 offsets the original mix used). Clamped to the
-- 13-bit range rather than wrapped, so a loud overlap clips instead of
-- jumping to the far rail.
mix <= signed("00000" & ay1_audio & '0') + signed("00000" & ay2_audio & '0')
     + adpcm_mix + 4096;
audio <= (others => '0') when mix < 0 else
         (others => '1') when mix > 8191 else
         std_logic_vector(mix(12 downto 0));
audio_out <= audio(12 downto 1);
 
-- microprocessor 6800/01/03
main_cpu : entity work.cpu68
port map(	
 clk      => clock_E,   -- E clock input (falling edge)
 rst      => reset,    -- reset input (active high)
 rw       => cpu_rw,   -- read not write output
 vma      => cpu_vma,  -- valid memory address (active high)
 address  => cpu_addr, -- address bus output
 data_in  => cpu_di,   -- data bus input
 data_out => cpu_do,   -- data bus output
 hold     => '0',      -- hold input (active high) extend bus cycle
 halt     => '0',      -- halt input (active high) grants DMA
 irq      => cpu_irq,  -- interrupt request input (active high)
 nmi      => cpu_nmi,  -- non maskable interrupt request input (active high)
 test_alu => open,
 test_cc  => open
);

snd_vma <= rom_cs and cpu_vma;

snd_rom_addr <= cpu_addr(15 downto 0);


-- cpu wram
cpu_ram : entity work.spram
generic map( widthad_a => 7)
port map(
 clock  => clock_E,
 wren   => wram_we,
 address => cpu_addr(6 downto 0),
 data    => cpu_do,
 q    => wram_do
);

  ay83910_inst1: YM2149
  port map (
    CLK         => clock_E,
    CE          => '1',
    RESET       => reset,
    A8          => '1',
    A9_L        => port2_data(4),
    BDIR        => port2_data(0),
    BC          => port2_data(2),
    DI          => port1_data,
    DO          => ay1_do,
    CHANNEL_A   => ay1_chan_a,
    CHANNEL_B   => ay1_chan_b,
    CHANNEL_C   => ay1_chan_c,

    SEL         => '0',
    MODE        => '1',

    ACTIVE      => open,

    IOA_in      => select_sound_r,
    IOA_out     => open,

    IOB_in      => (others => '0'),
    IOB_out     => ay1_port_b_do
    );

  ay1_audio <= "0000000000" + ay1_chan_a + ay1_chan_b + ay1_chan_c;

  ay83910_inst2: YM2149
  port map (
    CLK         => clock_E,
    CE          => '1',
    RESET       => reset,
    A8          => '1',
    A9_L        => port2_data(3),
    BDIR        => port2_data(0),
    BC          => port2_data(2),
    DI          => port1_data,
    DO          => ay2_do,
    CHANNEL_A   => ay2_chan_a,
    CHANNEL_B   => ay2_chan_b,
    CHANNEL_C   => ay2_chan_c,

    SEL         => '0',
    MODE        => '1',

    ACTIVE      => open,

    IOA_in      => (others => '0'),
    IOA_out     => open,

    IOB_in      => (others => '0'),
    IOB_out     => open
    );

  ay2_audio <= "0000000000" + ay2_chan_a + ay2_chan_b + ay2_chan_c;

end struct;