/*
---------------------------------------------------------------------------------------------------
    Aarhus University (AU, Denmark)
---------------------------------------------------------------------------------------------------

    File: neuron_memory.vhd
    Description: Initializing BRAM from an external data file.

    Link(s):
        - https://docs.amd.com/r/en-US/ug901-vivado-synthesis

---------------------------------------------------------------------------------------------------

    Functionality:
        - Block RAM initialized from external data file (neuron_memory_init.data).
        - External data must be in bit vector form.
        - The RAM is 256x32 bits.
        - Indexed by an 8-bit address.

---------------------------------------------------------------------------------------------------
*/

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity neuron_memory is
    port (
        clk  : in  std_logic;
        we   : in  std_logic;
        addr : in  std_logic_vector(7 downto 0);
        din  : in  std_logic_vector(31 downto 0);
        dout : out std_logic_vector(31 downto 0)
    );
end neuron_memory;

architecture syn of neuron_memory is
    type RamType is array (0 to 255) of bit_vector(31 downto 0);

    impure function InitRamFromFile(RamFileName : in string) return RamType is
        FILE RamFile         : text is in RamFileName;
        variable RamFileLine : line;
        variable RAM         : RamType;
    begin
        for I in RamType'range loop
            readline(RamFile, RamFileLine);
            read(RamFileLine, RAM(I));
        end loop;
        return RAM;
    end function;

    signal RAM : RamType := InitRamFromFile("data/nrn_init.data");

begin
    process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                RAM(to_integer(unsigned(addr))) <= to_bitvector(din);
            end if;
            dout <= to_stdlogicvector(RAM(to_integer(unsigned(addr))));
        end if;
    end process;
end syn;

