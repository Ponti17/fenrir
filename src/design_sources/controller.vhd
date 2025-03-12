/*
---------------------------------------------------------------------------------------------------
    Aarhus University (AU, Denmark)
---------------------------------------------------------------------------------------------------

    File: controller.vhd
    Description: Controller for 8x6 SNN.

    Author(s):
        - A. Pedersen, Aarhus University
        - A. Cherencq, Aarhus University

---------------------------------------------------------------------------------------------------

    Functionality:
        - Controller for 8x6 SNN.

---------------------------------------------------------------------------------------------------
*/

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controller is
    port (
        -- control
        clk             : in  std_logic;
        nRst            : in  std_logic;                        -- !reset signal (0 = reset)
        busy            : out std_logic;                        -- busy (1 = busy)
        data_rdy        : in  std_logic;                        -- data ready (1 = data ready)

        -- outputs
        out0            : out std_logic_vector(31 downto 0);    -- temp general purpose output
        out1            : out std_logic_vector(31 downto 0);    -- temp general purpose output
        out2            : out std_logic_vector(31 downto 0);    -- temp general purpose output

        -- memory
        ibf_addr        : out std_logic_vector(7 downto 0);     -- 8-bit address for input buffer
        ibf_in          : in  std_logic_vector(31 downto 0);    -- 32-bit input for synapse

        syn_addr        : out std_logic_vector(7 downto 0);     -- 8-bit address for synapse memory
        syn_in          : in  std_logic_vector(31 downto 0);    -- 32-bit value for synapse memory

        nrn_addr        : out std_logic_vector(7 downto 0);     -- 8-bit address for neuron memory
        nrn_in          : in  std_logic_vector(31 downto 0)     -- 32-bit value for neuron memory

        -- lif logic
        param_leak_str  : out std_logic_vector(6 downto 0);     -- leakage stength parameter
        param_thr       : out std_logic_vector(11 downto 0);    -- neuron firing threshold parameter

        state_core      : out std_logic_vector(11 downto 0);    -- core neuron state from SRAM

        syn_weight      : out std_logic_vector(3 downto 0);     -- synaptic weight
        syn_event       : out std_logic;                        -- synaptic event trigger
    );
end controller;

architecture Behavioral of controller is
    -- state machine
    type states is (
        IDLE,       -- idle state
        ITRT_NRN,   -- iterate neurons
        ITRT_SYN,   -- iterate synapses
        COMPUTE
    );
    signal cur_state                : states;

    -- input buffer address counter and value
    signal ibf_addr_cntr            : std_logic_vector(7 downto 0);  -- input buffer address counter
    signal ibf_val                  : std_logic_vector(31 downto 0); -- input buffer value

    -- synapse memory address counter and value
    signal syn_addr_cntr            : std_logic_vector(7 downto 0);  -- synapse memory address counter
    signal syn_val                  : std_logic_vector(31 downto 0); -- synapse memory value

    -- neuron memory address counter and value
    signal nrn_addr_cntr            : std_logic_vector(7 downto 0);  -- neuron memory address counter
    signal nrn_val                  : std_logic_vector(31 downto 0); -- neuron memory value

begin
    process(clk) is
    begin
        if rising_edge(clk) then
            -- reset state machine
            if nRst = '0' then
                cur_state <= IDLE;
                -- reset address counters
                ibf_addr_cntr   <= (others => '0');
                syn_addr_cntr   <= (others => '0');
                nrn_addr_cntr   <= (others => '0');
            else
                -- state machine
                case cur_state is

                    when IDLE =>
                        -- wait for data_rdy signal
                        busy <= '0';
                        -- reset address counters
                        ibf_addr_cntr   <= (others => '0');
                        syn_addr_cntr   <= (others => '0');
                        nrn_addr_cntr   <= (others => '0');
                        -- start reading if data is ready
                        if data_rdy = '1' then
                            cur_state <= ITRT_NRN;
                            busy <= '1';
                        end if;

                    when ITRT_NRN =>
                        -- set BRAM addresse
                        nrn_addr    <= nrn_addr_cntr;

                        -- read memory (delayed by one cycle)
                        nrn_val     <= nrn_in;

                        -- increment address counter
                        nrn_addr_cntr   <= std_logic_vector( unsigned(nrn_addr_cntr) + 1 );

                        -- iterate synapses for current neuron
                        cur_state <= ITRT_SYN;

                    when ITRT_SYN =>
                        -- set BRAM addresses
                        ibf_addr    <= ibf_addr_cntr;
                        syn_addr    <= syn_addr_cntr;

                        -- read memory (delayed by one cycle)
                        ibf_val     <= ibf_in;
                        syn_val     <= syn_in;

                        -- increment address counters
                        ibf_addr_cntr   <= std_logic_vector( unsigned(ibf_addr_cntr) + 1 );
                        syn_addr_cntr   <= std_logic_vector( unsigned(syn_addr_cntr) + 1 );

                        -- compute next neuron state
                        cur_state <= COMPUTE;

                    when COMPUTE =>
                        -- compute neuron states
                        out0 <= ibf_val;
                        out1 <= syn_val;
                        out2 <= nrn_val;

                        cur_state <= ITRT_SYN;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
