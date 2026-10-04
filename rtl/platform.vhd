library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;
use work.pace_pkg.all;
use work.video_controller_pkg.all;
use work.sprite_pkg.all;
use work.platform_pkg.all;
--use work.project_pkg.all;

entity platform is
  generic
  (
    NUM_INPUT_BYTES   : integer
  );
  port
  (
    -- clocking and reset
    clkrst_i        : in from_CLKRST_t;
    cpu_clk_en_i    : in std_logic;

    -- misc I/O
    buttons_i       : in from_BUTTONS_t;
    switches_i      : in from_SWITCHES_t;
    leds_o          : out to_LEDS_t;

    -- controller inputs
    inputs_i        : in from_MAPPED_INPUTS_t(0 to NUM_INPUT_BYTES-1);

    -- graphics
    
    bitmap_i        : in from_BITMAP_CTL_a(1 to PACE_VIDEO_NUM_BITMAPS);
    bitmap_o        : out to_BITMAP_CTL_a(1 to PACE_VIDEO_NUM_BITMAPS);
    
    tilemap_i       : in from_TILEMAP_CTL_a(1 to PACE_VIDEO_NUM_TILEMAPS);
    tilemap_o       : out to_TILEMAP_CTL_a(1 to PACE_VIDEO_NUM_TILEMAPS);

    sprite_reg_o    : out to_SPRITE_REG_t;
    sprite_i        : in from_SPRITE_CTL_t;
    sprite_o        : out to_SPRITE_CTL_t;
    spr0_hit        : in std_logic;
    sprite_pri      : out std_logic;
    sprite_opaque   : out std_logic;
    sprite_rgb      : out RGB_t;

    -- various graphics information
    graphics_i      : in from_GRAPHICS_t;
    graphics_o      : out to_GRAPHICS_t;
    sound_data_o    : out std_logic_vector(7 downto 0);

    -- custom i/o
--    project_i       : in from_PROJECT_IO_t;
--    project_o       : out to_PROJECT_IO_t;
    platform_i      : in from_PLATFORM_IO_t;
    platform_o      : out to_PLATFORM_IO_t;

    dl_addr         : in std_logic_vector(11 downto 0);
    dl_data         : in std_logic_vector(7 downto 0);
    dl_wr           : in std_logic;

    cpu_rom_addr    : out std_logic_vector(16 downto 0);
    cpu_rom_do      : in std_logic_vector(7 downto 0);
    gfx1_addr       : out std_logic_vector(17 downto 2);
    gfx1_do         : in std_logic_vector(31 downto 0);
    gfx2_addr       : out std_logic_vector(17 downto 2);
    gfx2_do         : in std_logic_vector(31 downto 0);

	 pause				: in std_logic;
	 
    -- high score
    hs_address       : in  std_logic_vector(11 downto 0);
    hs_data_out      : out std_logic_vector(7 downto 0);    
    hs_data_in       : in  std_logic_vector(7 downto 0);
    hs_write         : in  std_logic
);

end platform;

architecture SYN of platform is

  alias clk_sys         : std_logic is clkrst_i.clk(0);
  alias rst_sys         : std_logic is clkrst_i.rst(0);
  alias clk_video       : std_logic is clkrst_i.clk(1);

  -- cpu signals  
  signal cpu_clk_en     : std_logic;
  signal cpu_a          : std_logic_vector(15 downto 0);
  signal cpu_d_i        : std_logic_vector(7 downto 0);
  signal cpu_d_o        : std_logic_vector(7 downto 0);
  signal cpu_mem_wr     : std_logic;
  signal cpu_irq        : std_logic;
  signal cpu_intack     : std_logic;

  -- ROM signals        
  signal rom_cs         : std_logic;
--  signal rom_d_o        : std_logic_vector(7 downto 0);
  
  -- keyboard signals

  -- VRAM signals       
  signal vram_cs        : std_logic;
  signal vram_wr        : std_logic;
  signal vram_d_o       : std_logic_vector(7 downto 0);

  signal snd_cs         : std_logic;

  -- RAM signals        
  signal wram_cs        : std_logic;
  signal wram_wr        : std_logic;
  signal wram_d_o       : std_logic_vector(7 downto 0);

  -- CRAM/SPRITE signals        
  signal cram_cs        : std_logic;
  signal cram_wr        : std_logic;
  signal cram_d_o       : std_logic_vector(7 downto 0);
  signal sprite_cs      : std_logic;


  -- misc signals      
  signal in_cs          : std_logic;
  signal in_d_o         : std_logic_vector(7 downto 0);
  -- M58 colour ladders. MAME resnet weights (220/470/1000 ohm, common scale):
  -- 3-bit ladder 0,33,71,104,151,184,222,255 - 2-bit ladder 0,71,151,222.
  -- Bit order is (220, 470, 1000), matching promval(5 downto 3) for green,
  -- promval(2 downto 0) for blue and promval(7 downto 6) for red.
  function m58_level3 (b : std_logic_vector(2 downto 0)) return std_logic_vector is
  begin
    case b is
      when "000" => return x"00";
      when "001" => return x"21";
      when "010" => return x"47";
      when "011" => return x"68";
      when "100" => return x"97";
      when "101" => return x"B8";
      when "110" => return x"DE";
      when others => return x"FF";
    end case;
  end function;

  function m58_level2 (b : std_logic_vector(1 downto 0)) return std_logic_vector is
  begin
    case b is
      when "00" => return x"00";
      when "01" => return x"51";
      when "10" => return x"AE";
      when others => return x"FF";
    end case;
  end function;

  -- M58 packed colour byte: high nibble from char_hipal, low from char_lopal
  signal m58_promval    : std_logic_vector(7 downto 0);

  -- M58 sprite ladders: same networks as the characters but with a 470 ohm
  -- pulldown, so every level is lower.
  function m58_spr_level3 (b : std_logic_vector(2 downto 0)) return std_logic_vector is
  begin
    case b is
      when "000" => return x"00";
      when "001" => return x"1A";
      when "010" => return x"37";
      when "011" => return x"51";
      when "100" => return x"76";
      when "101" => return x"90";
      when "110" => return x"AE";
      when others => return x"C8";
    end case;
  end function;

  function m58_spr_level2 (b : std_logic_vector(1 downto 0)) return std_logic_vector is
  begin
    case b is
      when "00" => return x"00";
      when "01" => return x"3E";
      when "10" => return x"84";
      when others => return x"C1";
    end case;
  end function;

  signal sp_pal_r_q     : std_logic_vector(7 downto 0);
  signal sp_pal_g_q     : std_logic_vector(7 downto 0);
  signal sp_pal_r_a     : std_logic_vector(7 downto 0);

  -- M58 score panel bitmap (0x9000-0x9fff) and its packed radar colour byte
  signal panel_cs       : std_logic;
  signal panel_wr       : std_logic;
  signal panel_q        : std_logic_vector(7 downto 0);
  signal m58_radarval   : std_logic_vector(7 downto 0);
  signal pal_r_wr       : std_logic;
  signal pal_g_wr       : std_logic;
  signal sp_pal_r_wr    : std_logic;
  signal sp_pal_g_wr    : std_logic;
  signal pal_r_q        : std_logic_vector(7 downto 0);
  signal pal_g_q        : std_logic_vector(7 downto 0);

  signal pal2_r_wr      : std_logic;
  signal pal2_g_wr      : std_logic;
  signal pal2_r_q       : std_logic_vector(7 downto 0);
  signal pal2_g_q       : std_logic_vector(7 downto 0);

  -- other signals
  signal rst_platform   : std_logic;
--  signal pause          : std_logic;
  signal rot_en         : std_logic;


begin

  -- handle special keys
  process (clk_sys, rst_sys)
    variable spec_keys_r  : std_logic_vector(7 downto 0);
    alias spec_keys       : std_logic_vector(7 downto 0) is inputs_i(PACE_INPUTS_NUM_BYTES-1).d;
    variable layer_en     : std_logic_vector(4 downto 0);
  begin
    if rst_sys = '1' then
      rst_platform <= '0';
--      pause <= '0';
      rot_en <= '0';  -- to default later
      spec_keys_r := (others => '0');
      layer_en := "11111";
    elsif rising_edge(clk_sys) then
      rst_platform <= spec_keys(0);
--      if spec_keys_r(1) = '0' and spec_keys(1) = '1' then
--        pause <= not pause;
--      end if;
      if spec_keys_r(2) = '0' and spec_keys(2) = '1' then
        rot_en <= not rot_en;
        if layer_en = "11111" then
          layer_en := "00001";
        elsif layer_en = "10000" then
          layer_en := "11111";
        else
          layer_en := layer_en(3 downto 0) & layer_en(4);
        end if;
      end if;
      spec_keys_r := spec_keys;
    end if;
    graphics_o.bit8(0)(4 downto 0) <= layer_en;
  end process;
  
  --graphics_o.bit8(0)(0) <= rot_en;
  
  -- chip select logic (M58 memory map, all memory-mapped - no Z80 port I/O)
  -- ROM    $0000-$7FFF
  rom_cs <=     '1' when cpu_a(15) = '0' else '0';

  -- VRAM/CRAM $8000-$8FFF, interleaved: even bytes tile, odd bytes attribute
  vram_cs <=    '1' when STD_MATCH(cpu_a, X"8"&"-----------0") else '0';
  cram_cs <=    '1' when STD_MATCH(cpu_a, X"8"&"-----------1") else '0';

  -- score panel bitmap $9000-$9FFF
  panel_cs <=   '1' when cpu_a(15 downto 12) = x"9" else '0';

  -- SPRITE $C800-$C8FF
  sprite_cs <=  '1' when cpu_a(15 downto 8) = x"C8" else '0';

  -- sound command $D000, inputs $D000-$D004
  snd_cs <=     '1' when cpu_a = X"D000" else '0';
  in_cs <=      '1' when STD_MATCH(cpu_a, X"D00"&"0---") else '0';

  -- RAM $E000-$EFFF
  wram_cs <=    '1' when STD_MATCH(cpu_a, X"E"&"------------") else '0';

  process (clk_sys, rst_sys) begin
    if rst_sys = '1' then
      sound_data_o <= X"00";
    elsif rising_edge(clk_sys) then
      if cpu_clk_en = '1' and cpu_mem_wr = '1' and snd_cs = '1' then
        sound_data_o <= cpu_d_o;
      end if;
    end if; 
  end process;

  -- memory read mux
  cpu_d_i <=  in_d_o when in_cs = '1' else
              cpu_rom_do when rom_cs = '1' else
              vram_d_o when vram_cs = '1' else
              cram_d_o when cram_cs = '1' else
              wram_d_o when wram_cs = '1' else
              (others => '1');

  -- memory block write signals 
  vram_wr <= vram_cs and cpu_mem_wr;
  cram_wr <= cram_cs and cpu_mem_wr;
  wram_wr <= wram_cs and cpu_mem_wr;
  panel_wr <= panel_cs and cpu_mem_wr;

  -- sprite registers
  sprite_reg_o.clk <= clk_sys;
  sprite_reg_o.clk_ena <= cpu_clk_en_i;
  sprite_reg_o.a <= '0' & cpu_a(7 downto 0);
  sprite_reg_o.d <= cpu_d_o;
  sprite_reg_o.wr <= sprite_cs and cpu_mem_wr;

  --
  -- COMPONENT INSTANTIATION
  --

  BLK_CPU : block
    signal cpu_rst        : std_logic;
  begin
    -- gated CPU signals
    cpu_clk_en <= cpu_clk_en_i and not pause;
    cpu_rst <= rst_sys or rst_platform;
    
    cpu_inst : entity work.Z80                                                
      port map
      (
        clk     => clk_sys,                                   
        clk_en  => cpu_clk_en,
        reset   => cpu_rst,

        addr    => cpu_a,
        datai   => cpu_d_i,
        datao   => cpu_d_o,

        mem_rd  => open,
        mem_wr  => cpu_mem_wr,
        io_rd   => open,
        io_wr   => open,

        intreq  => cpu_irq,
        intvec  => cpu_d_i,
        intack  => cpu_intack,
        nmi     => '0'
      );

    cpu_rom_addr <= '0' & cpu_a(15 downto 0);
  end block BLK_CPU;

  BLK_INTERRUPTS : block
  
    signal vblank_r     : std_logic;

  begin

    -- generate INT
    process (clk_sys, rst_sys)
    begin
      if rst_sys = '1' then
        cpu_irq <= '0';
      elsif rising_edge(clk_sys) then
        vblank_r <= graphics_i.vblank;
        if vblank_r = '0' and graphics_i.vblank = '1' then
          cpu_irq <= '1';
        end if;
        if cpu_intack = '1' then
          cpu_irq <= '0';
        end if;
      end if;
    end process;

  end block BLK_INTERRUPTS;

  BLK_INPUTS : block
  begin
    in_d_o <= inputs_i(0).d when cpu_a(2 downto 0) = "000" else
              inputs_i(1).d when cpu_a(2 downto 0) = "001" else
              inputs_i(2).d when cpu_a(2 downto 0) = "010" else
              inputs_i(3).d when cpu_a(2 downto 0) = "011" else
              inputs_i(4).d;
  end block BLK_INPUTS;
  
  BLK_SCROLL : block
    signal hscroll      : std_logic_vector(15 downto 0);
    signal vscroll      : std_logic_vector(15 downto 0);
    -- score panel blanking (0xa800)
    signal m58_panel_disable : std_logic := '0';
    -- Cocktail flip. The board's FLIP node is the CPU's latched bit
    -- combined with the physical dip, and the dip sits on that node
    -- continuously - it is not sampled when the CPU writes. So latch only
    -- the software bit here and xor the live dip on the way out.
    signal m58_flip_sw       : std_logic := '0';
    signal m58_flip          : std_logic;
  begin
    process (clk_sys, rst_sys)
    begin
      if rst_sys = '1' then
        hscroll <= (others => '0');
        vscroll <= (others => '0');
      elsif rising_edge(clk_sys) then
        if cpu_clk_en = '1' and cpu_mem_wr = '1' then
          case cpu_a is
            when X"A000" =>
              hscroll(7 downto 0) <= cpu_d_o;
            when X"A200" =>
              hscroll(15 downto 8) <= cpu_d_o;
            when X"A400" =>
              vscroll(7 downto 0) <= cpu_d_o;
            when X"A800" =>
              -- MAME tests the whole byte, so treat any non-zero as disabled
              if cpu_d_o = x"00" then
                m58_panel_disable <= '0';
              else
                m58_panel_disable <= '1';
              end if;
            when x"D001" =>
              m58_flip_sw <= cpu_d_o(0);
            when others =>
              null;
          end case;
        end if; -- cpu_wr
      end if; -- rising_edge(clk_sys)
    end process;
    graphics_o.bit16(0) <= hscroll;
    graphics_o.bit16(1) <= vscroll;
    graphics_o.bit16(3)(1) <= m58_panel_disable;
    -- flip_screen_set(BIT(data,0) ^ BIT(~dsw2,0)): the dip reads 1 for
    -- Off, so invert it before the xor.
    m58_flip <= m58_flip_sw xor (not inputs_i(4).d(0));
    graphics_o.bit16(3)(2) <= m58_flip;
  end block BLK_SCROLL;


  BLK_GFX_ROMS : block
  begin

    -- external background ROMs
    gfx1_addr <= "00" & tilemap_i(1).tile_a(13 downto 0);

    tilemap_o(1).tile_d(23 downto 0) <= gfx1_do(7 downto 0) & gfx1_do(15 downto 8) & gfx1_do(23 downto 16);

    -- the score panel is a bitmap: no tile ROM, no attributes
    tilemap_o(2).tile_d(23 downto 0) <= (others => '0');

    -- external sprite ROMs
    gfx2_addr <= sprite_i.a(15 downto 0);
    sprite_o.d(23 downto 0) <= gfx2_do(7 downto 0) & gfx2_do(15 downto 8) & gfx2_do(23 downto 16);

  end block BLK_GFX_ROMS;

  BLK_VRAM : block
    signal vram_a   : std_logic_vector(11 downto 0);
    alias cram_a    : std_logic_vector(11 downto 0) is vram_a;
  begin

    vram_a <= '0' & cpu_a(11 downto 1);

    vram_inst : entity work.dpram
      generic map
      (
        init_file  => "",
        widthad_a  => 12,
        widthad_b  => 12
      )
      port map
      (
        clock_b    => clk_sys,
        address_b  => vram_a,
        wren_b     => vram_wr,
        data_b     => cpu_d_o,
        q_b        => vram_d_o,

        clock_a    => clk_video,
        address_a  => tilemap_i(1).map_a(11 downto 0),
        wren_a     => '0',
        data_a     => (others => 'X'),
        q_a        => tilemap_o(1).map_d(7 downto 0)
      );
    tilemap_o(1).map_d(15 downto 8) <= (others => '0');

    cram_inst : entity work.dpram
      generic map
      (
        init_file  => "",
        widthad_a  => 12,
        widthad_b  => 12
      )
      port map
      (
        clock_b     => clk_sys,
        address_b   => cram_a,
        wren_b      => cram_wr,
        data_b      => cpu_d_o,
        q_b         => cram_d_o,

        clock_a     => clk_video,
        address_a   => tilemap_i(1).attr_a(11 downto 0),
        wren_a      => '0',
        data_a      => (others => 'X'),
        q_a         => tilemap_o(1).attr_d(7 downto 0)
      );
    tilemap_o(1).attr_d(15 downto 8) <= (others => '0');

    tilemap_o(2).attr_d(7 downto 0) <= (others => '0');
    tilemap_o(2).map_d(7 downto 0) <= panel_q;

    -- score panel bitmap: 16 bytes per row, 256 rows
    panel_ram : entity work.dpram
      generic map
      (
        init_file  => "",
        widthad_a  => 12,
        widthad_b  => 12
      )
      port map
      (
        clock_b     => clk_sys,
        address_b   => cpu_a(11 downto 0),
        wren_b      => panel_wr,
        data_b      => cpu_d_o,
        q_b         => open,

        clock_a     => not clk_video,
        address_a   => tilemap_i(2).map_a(11 downto 0),
        wren_a      => '0',
        data_a      => (others => '0'),
        q_a         => panel_q
      );

  end block BLK_VRAM;

--  wram_inst : entity work.spram
--    generic map
--    (
--      widthad_a => 12
--    )
--    port map
--    (
--      clock     => clk_sys,
--      address   => cpu_a(11 downto 0),
--      data      => cpu_d_o,
--      wren      => wram_wr,
--      q         => wram_d_o
--    );
    wram_inst : entity work.dpram
      generic map
      (
        init_file  => "",
        widthad_a  => 12,
        width_a    => 8,
        widthad_b  => 12,
        width_b    => 8
     )
      port map
      (
        clock_a     => clk_sys,
        address_a   => cpu_a(11 downto 0),
        wren_a      => wram_wr,
        data_a      => cpu_d_o,
        q_a         => wram_d_o,
		  
        clock_b     => clk_sys,
        address_b   => hs_address,
        wren_b      => hs_write,
        data_b      => hs_data_in,
        q_b         => hs_data_out

      );
  -- A colour is packed into two 4-bit PROMs feeding resistor ladders.
  m58_promval <= pal_g_q(3 downto 0) & pal_r_q(3 downto 0);

  tilemap_o(1).rgb.r(9 downto 2) <= m58_level2(m58_promval(7 downto 6));
  tilemap_o(1).rgb.g(9 downto 2) <= m58_level3(m58_promval(5 downto 3));
  tilemap_o(1).rgb.b(9 downto 2) <= m58_level3(m58_promval(2 downto 0));

  -- tilemap 1 palettes
  pal_r : entity work.dpram
    generic map
    (
      init_file  => "",
      widthad_a  => 8,
      widthad_b  => 8
    )
    port map
    (
      clock_b     => clk_sys,
      address_b   => dl_addr(7 downto 0),
      wren_b      => pal_r_wr,
      data_b      => dl_data,
      q_b         => open,

      clock_a     => not clk_video,
      address_a   => tilemap_i(1).pal_a(7 downto 0),
      wren_a      => '0',
      data_a      => (others => 'X'),
      q_a         => pal_r_q
    );
  pal_r_wr <= '1' when dl_wr = '1' and dl_addr(11 downto 8) = x"3" else '0';  -- 300-3FF

  pal_g : entity work.dpram
    generic map
    (
      init_file  => "",
      widthad_a  => 8,
      widthad_b  => 8
    )
    port map
    (
      clock_b     => clk_sys,
      address_b   => dl_addr(7 downto 0),
      wren_b      => pal_g_wr,
      data_b      => dl_data,
      q_b         => open,

      clock_a     => not clk_video,
      address_a   => tilemap_i(1).pal_a(7 downto 0),
      wren_a      => '0',
      data_a      => (others => 'X'),
      q_a         => pal_g_q
    );
  pal_g_wr <= '1' when dl_wr = '1' and dl_addr(11 downto 8) = x"4" else '0';  -- 400-4FF


  -- The radar palette is packed the same way as the character palette and
  -- uses the same ladders (MAME computes both in one call, no pulldown).
  m58_radarval <= pal2_g_q(3 downto 0) & pal2_r_q(3 downto 0);

  tilemap_o(2).rgb.r(9 downto 2) <= m58_level2(m58_radarval(7 downto 6));
  tilemap_o(2).rgb.g(9 downto 2) <= m58_level3(m58_radarval(5 downto 3));
  tilemap_o(2).rgb.b(9 downto 2) <= m58_level3(m58_radarval(2 downto 0));

  -- tilemap 2 palettes
  pal2_r : entity work.dpram
    generic map
    (
      init_file  => "",
      widthad_a  => 8,
      widthad_b  => 8
    )
    port map
    (
      clock_b     => clk_sys,
      address_b   => dl_addr(7 downto 0),
      wren_b      => pal2_r_wr,
      data_b      => dl_data,
      q_b         => open,

      clock_a     => not clk_video,
      address_a   => tilemap_i(2).pal_a(7 downto 0),
      wren_a      => '0',
      data_a      => (others => 'X'),
      q_a         => pal2_r_q
    );
  pal2_r_wr <= '1' when dl_wr = '1' and dl_addr(11 downto 8) = x"6" else '0';  -- 600-6FF

  pal2_g : entity work.dpram
    generic map
    (
      init_file  => "",
      widthad_a  => 8,
      widthad_b  => 8
    )
    port map
    (
      clock_b     => clk_sys,
      address_b   => dl_addr(7 downto 0),
      wren_b      => pal2_g_wr,
      data_b      => dl_data,
      q_b         => open,

      clock_a     => not clk_video,
      address_a   => tilemap_i(2).pal_a(7 downto 0),
      wren_a      => '0',
      data_a      => (others => 'X'),
      q_a         => pal2_g_q
    );
  pal2_g_wr <= '1' when dl_wr = '1' and dl_addr(11 downto 8) = x"7" else '0';  -- 700-7FF

  -- The two sprite PROMs are chained: colour&pel indexes the lookup table in
  -- sp_pal_g, and its low nibble indexes the 16-entry palette in sp_pal_r.
  sp_pal_r_a <= "0000" & sp_pal_g_q(3 downto 0);

  sprite_rgb.r(9 downto 2) <= m58_spr_level2(sp_pal_r_q(7 downto 6));
  sprite_rgb.g(9 downto 2) <= m58_spr_level3(sp_pal_r_q(5 downto 3));
  sprite_rgb.b(9 downto 2) <= m58_spr_level3(sp_pal_r_q(2 downto 0));

  -- Sprite transparency comes from the lookup table, not the pixel value.
  -- Registered so it lines up with the second lookup's output.
  process (clk_video)
  begin
    if falling_edge(clk_video) then
      if sp_pal_g_q(3 downto 0) = "0000" then
        sprite_opaque <= '0';
      else
        sprite_opaque <= '1';
      end if;
    end if;
  end process;

  -- sprite palettes
  sp_pal_r : entity work.dpram
    generic map
    (
      init_file  => "",
      widthad_a  => 8,
      widthad_b  => 8
    )
    port map
    (
      clock_b     => clk_sys,
      address_b   => dl_addr(7 downto 0),
      wren_b      => sp_pal_r_wr,
      data_b      => dl_data,
      q_b         => open,

      clock_a     => not clk_video,
      address_a   => sp_pal_r_a,
      wren_a      => '0',
      data_a      => (others => '0'),
      q_a         => sp_pal_r_q
    );
  sp_pal_r_wr <= '1' when dl_wr = '1' and dl_addr(11 downto 8) = x"0" else '0';  -- 000-0FF

  sp_pal_g : entity work.dpram
    generic map
    (
      init_file  => "",
      widthad_a  => 8,
      widthad_b  => 8
    )
    port map
    (
      clock_b     => clk_sys,
      address_b   => dl_addr(7 downto 0),
      wren_b      => sp_pal_g_wr,
      data_b      => dl_data,
      q_b         => open,

      clock_a     => not clk_video,
      address_a   => sprite_i.pal_a,
      wren_a      => '0',
      data_a      => (others => '0'),
      q_a         => sp_pal_g_q
    );
  sp_pal_g_wr <= '1' when dl_wr = '1' and dl_addr(11 downto 8) = x"1" else '0';  -- 100-1FF

  -- sprites always sit over the background: the tilemap never sets prio
  sprite_pri <= not tilemap_i(1).prio;

  -- unused outputs

  sprite_o.ld <= '0';
  --graphics_o <= NULL_TO_GRAPHICS;
  leds_o <= (others => '0');
  
end SYN;
