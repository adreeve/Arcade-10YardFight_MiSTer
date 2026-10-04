Library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sprite_pkg.all;

entity sptReg is

	generic
	(
		INDEX			: natural
	);
	port
	(
    reg_i     : in to_SPRITE_REG_t;
    reg_o     : out from_SPRITE_REG_t
	);

end sptReg;

architecture SYN of sptReg is

  alias clk       : std_logic is reg_i.clk;
  alias clk_ena   : std_logic is reg_i.clk_ena;

begin

  process (clk, clk_ena)
  begin
    if rising_edge(clk) then
      if clk_ena = '1' then
        -- 4 bytes per entry, so the slot index is a(7 downto 2)
        if reg_i.a(7 downto 2) = std_logic_vector(to_unsigned(INDEX, 6)) then
          if reg_i.wr = '1' then
            case reg_i.a(1 downto 0) is
              when "00" =>
                -- y is inverted (sy = 210 - v)
                reg_o.y(8 downto 0) <= std_logic_vector(to_unsigned(126, 9) + unsigned(reg_i.d));
              when "01" =>
                reg_o.colour(4 downto 0) <= reg_i.d(4 downto 0);
                reg_o.n(8) <= reg_i.d(5);   -- bank
                reg_o.xflip <= reg_i.d(6);
                reg_o.yflip <= reg_i.d(7);
              when "10" =>
                reg_o.n(10 downto 9) <= "00";
                reg_o.n(7) <= reg_i.d(7);
                reg_o.n(6) <= '0';          -- code & 0xbf; bit 6 set per segment
                reg_o.n(5 downto 0) <= reg_i.d(5 downto 0);
              when others =>
                reg_o.x(7 downto 0) <= reg_i.d;
                reg_o.x(8) <= '0';
            end case;
          end if; -- reg_i.wr='1'
        end if; -- reg_i.a()=INDEX
      end if; -- clk_ena='1'
    end if; -- rising_edge(clk)
  end process;

  reg_o.x(reg_o.x'left downto 9) <= (others => '0');
  reg_o.y(reg_o.y'left downto 9) <= (others => '0');
  reg_o.n(reg_o.n'left downto 11) <= (others => '0');
  reg_o.colour(reg_o.colour'left downto 5) <= (others => '0');
  reg_o.pri <= '1';

end SYN;

