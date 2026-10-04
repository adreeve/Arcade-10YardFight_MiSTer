library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pace_pkg.all;
--use work.project_pkg.all;
use work.platform_pkg.all;
use work.video_controller_pkg.all;

--
--  Irem M58 Tilemap Controller
--
--  TILEMAP_1 is the 3bpp scrolling playfield, TILEMAP_2 the score panel
--  bitmap.
--
entity tilemapCtl is
  generic
  (
    DELAY       : integer
  );
  port
  (
    reset       : in std_logic;

    -- video control signals
    video_ctl   : in from_VIDEO_CTL_t;

    -- tilemap controller signals
    ctl_i       : in to_TILEMAP_CTL_t;
    ctl_o       : out from_TILEMAP_CTL_t;

    graphics_i  : in to_GRAPHICS_t
  );
end entity tilemapCtl;

architecture TILEMAP_1 of tilemapCtl is

  alias clk       : std_logic is video_ctl.clk;
  alias clk_ena   : std_logic is video_ctl.clk_ena;
  alias stb       : std_logic is video_ctl.stb;
  alias hblank    : std_logic is video_ctl.hblank;
  alias vblank    : std_logic is video_ctl.vblank;
  
  signal x        : std_logic_vector(video_ctl.x'range);
  signal y        : std_logic_vector(video_ctl.y'range);
  
  alias rot_en    : std_logic is graphics_i.bit8(0)(0);
  alias hscroll   : std_logic_vector(15 downto 0) is graphics_i.bit16(0);
  alias vscroll   : std_logic_vector(15 downto 0) is graphics_i.bit16(1);

  -- cocktail flip
  signal m58_flip : std_logic;
  -- Flipped, x counts down, so the three fetch stages move to the
  -- complementary phases to keep their order and their spacing.
  signal ph_map   : std_logic_vector(2 downto 0);   -- stage 1
  signal ph_tile  : std_logic_vector(2 downto 0);   -- stage 2
  signal ph_latch : std_logic_vector(2 downto 0);   -- stage 3

begin

  m58_flip <= graphics_i.bit16(3)(2);
  ph_map   <= "111" when m58_flip = '1' else "000";
  ph_tile  <= "110" when m58_flip = '1' else "001";
  ph_latch <= "000" when m58_flip = '1' else "111";

  ctl_o.rgb <= ctl_i.rgb;

  -- not used
  ctl_o.map_a(ctl_o.map_a'left downto 12) <= (others => '0');
  ctl_o.attr_a(ctl_o.attr_a'left downto 12) <= (others => '0');
  ctl_o.tile_a(ctl_o.tile_a'left downto 15) <= (others => '0');

  -- tilemap scroll

  -- The visible area starts at bitmap x 0, so the leftmost pixel fetches
  -- tilemap column scrollx + 0.
  -- Flipped, the screen is mirrored: 255 - x. The mirrored value drives
  -- the fetch phase too, so the 8-pixel pipeline still lines up.
  -- -8 rather than +8: running backwards the fetch leads by a group
  -- in the other direction, so the tile lands 16 pixels further right
  x <= std_logic_vector(255 - (unsigned(video_ctl.x) - 256) + unsigned(hscroll(8 downto 0)) - 8)
         when m58_flip = '1' else
       std_logic_vector(unsigned(video_ctl.x) - 256 + unsigned(hscroll(8 downto 0)) + 8);
  -- flipped: the visible window is y 16..239, so 255 - y mirrors it
  y <= std_logic_vector(255 - (unsigned(video_ctl.y) - 256) + unsigned(vscroll(8 downto 0)))
         when m58_flip = '1' else
       std_logic_vector(unsigned(video_ctl.y) - 256 + unsigned(vscroll(8 downto 0)));

  -- generate pixel
  process (clk, clk_ena)

    variable tile_d_r   : std_logic_vector(23 downto 0);
    variable attr_d_r   : std_logic_vector(7 downto 0);
    variable flipx      : std_logic;
    variable pel        : std_logic_vector(2 downto 0);

  begin
  
    if rising_edge(clk) then
      if clk_ena = '1' then

        -- 1st stage of pipeline
        -- - set tilemap, attribute address
        if x(2 downto 0) = ph_map then
          -- the 64x32 map is stored as two 32-column halves:
          -- entry address is col(5) & row(4:0) & col(4:0)
          ctl_o.map_a(11) <= '0';
          ctl_o.attr_a(11) <= '0';
          ctl_o.map_a(10) <= x(8);
          ctl_o.attr_a(10) <= x(8);
          ctl_o.map_a(9 downto 5) <= y(7 downto 3);
          ctl_o.attr_a(9 downto 5) <= y(7 downto 3);
          ctl_o.map_a(4 downto 0) <= x(7 downto 3);
          ctl_o.attr_a(4 downto 0) <= x(7 downto 3);
        end if;

        -- 2nd stage of pipeline
        -- - set tile address
        if x(2 downto 0) = ph_tile then
          ctl_o.tile_a(14 downto 13) <= "00";
          ctl_o.tile_a(12 downto 11) <= ctl_i.attr_d(7 downto 6);
          ctl_o.tile_a(10 downto 3) <= ctl_i.map_d(7 downto 0);
          ctl_o.tile_a(2 downto 0) <= y(2 downto 0);
        end if;

        -- 3rd stage of pipeline
        -- - read tile, attribute data from ROM
        if x(2 downto 0) = ph_latch then
          attr_d_r := ctl_i.attr_d(7 downto 0);
          -- flipped, every tile's pixel order reverses as well
          flipx := attr_d_r(5) xor m58_flip;
          tile_d_r := ctl_i.tile_d(tile_d_r'range);
        elsif stb = '1' then
          if flipx = '0' then
            tile_d_r := tile_d_r(tile_d_r'left-1 downto 0) & '0';
          else
            tile_d_r := '0' & tile_d_r(tile_d_r'left downto 1);
          end if;
        end if;

        -- extract R,G,B from colour palette
        if flipx = '0' then
          pel := tile_d_r(tile_d_r'left-16) & tile_d_r(tile_d_r'left-8) & tile_d_r(tile_d_r'left);
        else
          pel := tile_d_r(tile_d_r'right) & tile_d_r(tile_d_r'right+8) & tile_d_r(tile_d_r'right+16);
        end if;

        ctl_o.pal_a <= attr_d_r(4 downto 0) & pel;
        -- sprites always sit over the playfield
        ctl_o.prio <= '0';
        ctl_o.set <= '0'; -- default
--        if pel /= "000" then
--            pal_rgb(0)(7 downto 5) /= "000" or
--            pal_rgb(1)(7 downto 5) /= "000" or
--            pal_rgb(2)(7 downto 5) /= "000" then
--          if graphics_i.bit8(0)(3) = '1' then
            ctl_o.set <= '1';
--          end if;
--        end if;

      end if; -- clk_ena
    end if; -- rising_edge_clk

  end process;

end architecture TILEMAP_1;

-- Irem M58 score panel

architecture TILEMAP_2 of tilemapCtl is

  alias clk       : std_logic is video_ctl.clk;
  alias clk_ena   : std_logic is video_ctl.clk_ena;
  alias stb       : std_logic is video_ctl.stb;
  alias hblank    : std_logic is video_ctl.hblank;
  alias vblank    : std_logic is video_ctl.vblank;
  
  signal x        : std_logic_vector(video_ctl.x'range);
  signal y        : std_logic_vector(video_ctl.y'range);

  alias rot_en    : std_logic is graphics_i.bit8(0)(0);

  -- CENTER PCB sheet 4 of 4: the '157 at 6F puts H4E, H8, H16 and H32 on
  -- RAMA0..3, so the panel RAM column is h_eff(5 downto 2) and the pixel
  -- within the byte is h_eff(1 downto 0), h_eff being the counter after the
  -- flip XORs on BOTTOM sheet 1. The CPU port of the same mux takes A0..A3
  -- straight from the write address, so neither side carries an offset.
  --
  -- The pixel data lags the addressing counter by M58_PANEL_LAG: solving
  -- the board's column against MAME's unflipped picture gives 4 uniquely.
  --
  -- The window is not a mirror. It is PSOUT from the 74LS85 at 2B, which
  -- compares H64E/H32/H16/H8 (h_eff bits 6..3) against A = 8 + FLIP, with
  -- A3 strapped to +5V, A2/A1 to ground (pins 13, 12), A0 and the A=B and
  -- A>B cascade inputs on the FLIP net, and A<B-in on +5V. The FLIP net is
  -- high when NOT flipped; that is the only reading giving the known
  -- 48-pixel unflipped window, h_eff 208..255. Flipped it opens to h_eff
  -- 192..255 - screen x 0..63, 64 pixels wide - and with the data lag the
  -- content lands 8 pixels in: x 0..7 show RAM columns 0 and 15, which MAME
  -- never draws, and x 8..63 show panel source 55 down to 0.
  constant M58_PANEL_LAG : integer := 4;
  -- Measured, not derived: our own flipped path sits six pixels right of
  -- the model (hardware photo with both blanking edges visible). Confirmed
  -- on hardware with the result matching the board model.
  constant M58_PANEL_WIN_ADJ : integer := -6;

begin

  ctl_o.rgb <= ctl_i.rgb;
  --ctl_o.rgb.r <= x"aa"&"10";

  -- not used: the panel is a bitmap, with no attributes and no tile ROM
  ctl_o.map_a(ctl_o.map_a'left downto 12) <= (others => '0');
  ctl_o.attr_a <= (others => '0');
  ctl_o.tile_a <= (others => '0');
  ctl_o.prio <= '0';

  -- tilemap scroll
  -- The panel must run one pixel ahead of the display. Measured on
  -- hardware: at +2 a single column of background showed to its right, at
  -- +1 it sits flush with the screen edge.
  -- Flipped: panel_x = 63 - screen x, so source 55 lands at x 8 and the
  -- 64-pixel window below runs x 0..63. The counter mirrors but the data
  -- lag does not, hence the 2*LAG.
  x <= std_logic_vector(254 + 2*M58_PANEL_LAG + M58_PANEL_WIN_ADJ
                        - (unsigned(video_ctl.x) - 256))
         when graphics_i.bit16(3)(2) = '1' else
       std_logic_vector(unsigned(video_ctl.x) - 256 + 1);
  -- flipped: the visible rows are y 16..239, so 255 - y mirrors them
  y <= std_logic_vector(511 - unsigned(video_ctl.y))
         when graphics_i.bit16(3)(2) = '1' else
       std_logic_vector(unsigned(video_ctl.y) - 256);

  -- generate pixel
  process (clk, clk_ena)

    -- score panel
    variable panel_x    : unsigned(7 downto 0);
    variable panel_nx   : unsigned(7 downto 0);
    variable panel_d    : std_logic_vector(7 downto 0);
    variable panel_i    : integer range 0 to 3;
    variable panel_col  : std_logic_vector(1 downto 0);

  begin

    if rising_edge(clk) then
      if clk_ena = '1' then

        -- score panel: a CPU-written bitmap drawn over everything at
        -- screen x 208..255. The bitmap starts at x 200, so only pixels
        -- 8..55 of each 56-pixel row are visible, 4 pixels per byte.
        panel_x := unsigned(x(7 downto 0)) - 200;
        panel_nx := panel_x + 4;

        -- address the byte covering the next group of four pixels;
        -- driven every cycle, it only changes on group boundaries.
        -- Flipped, panel_x counts down, so the next group is the one
        -- below and its RAM column is group(panel_x) rather than +2.
        if graphics_i.bit16(3)(2) = '1' then
          ctl_o.map_a(11 downto 0) <= y(7 downto 0) &
                                      std_logic_vector(panel_x(5 downto 2));
        else
          ctl_o.map_a(11 downto 0) <= y(7 downto 0) &
                                      std_logic_vector(panel_nx(5 downto 2) + 1);
        end if;
        -- two bits per pixel, taken from bit i and bit i+4. This must
        -- read panel_d before the latch below: panel_d is a variable, so
        -- latching first would give the last pixel of every group the
        -- next group's byte.
        panel_i := to_integer(panel_x(1 downto 0));
        panel_col := panel_d(panel_i + 4) & panel_d(panel_i);

        -- latch at the end of a group going forwards, at its start
        -- going backwards
        if (graphics_i.bit16(3)(2) = '0' and x(1 downto 0) = "11") or
           (graphics_i.bit16(3)(2) = '1' and panel_x(1 downto 0) = "00") then
          panel_d := ctl_i.map_d(7 downto 0);
        end if;

        ctl_o.pal_a <= y(7 downto 2) & panel_col;

        ctl_o.set <= '0';
        -- PSOUT: 48 pixels unflipped, 64 flipped (see M58_PANEL_LAG)
        if graphics_i.bit16(3)(1) = '0' and
           ((graphics_i.bit16(3)(2) = '0' and panel_x >= 8 and panel_x <= 55) or
            (graphics_i.bit16(3)(2) = '1' and panel_x <= 63)) then
          ctl_o.set <= '1';
        end if;

      end if; -- clk_ena
    end if; -- rising_edge_clk

  end process;

end architecture TILEMAP_2;
