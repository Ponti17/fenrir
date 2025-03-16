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
        clk                 : in  std_logic;
        nRst                : in  std_logic;                        -- !reset signal (0 = reset)
        busy                : out std_logic;                        -- busy (1 = busy)
        data_rdy            : in  std_logic;                        -- data ready (1 = data ready)

        -- outputs
        out0                : out std_logic_vector(31 downto 0);    -- temp general purpose output
        out1                : out std_logic_vector(31 downto 0);    -- temp general purpose output
        out2                : out std_logic_vector(31 downto 0);    -- temp general purpose output

        -- memory
        ibf_addr            : out std_logic_vector(7 downto 0);     -- 8-bit address for input buffer
        ibf_in              : in  std_logic_vector(31 downto 0);    -- 32-bit input for synapse

        syn_addr            : out std_logic_vector(15 downto 0);    -- 8-bit address for synapse memory
        syn_in              : in  std_logic_vector(31 downto 0);    -- 32-bit value for synapse memory

        nrn_addr            : out std_logic_vector(7 downto 0);     -- 8-bit address for neuron memory
        nrn_in              : in  std_logic_vector(31 downto 0);    -- 32-bit value for neuron memory
        nrn_out             : out std_logic_vector(31 downto 0);    -- 32-bit value from neuron memory
        nrn_we              : out std_logic;                        -- write enable for neuron memory

        -- lif neuron
        param_leak_str      : out std_logic_vector(6 downto 0);     -- leakage stength parameter
        param_thr           : out std_logic_vector(11 downto 0);    -- neuron firing threshold parameter

        state_core          : out std_logic_vector(11 downto 0);    -- core neuron state from SRAM
        state_core_next     : in std_logic_vector(11 downto 0);     -- next core neuron state to SRAM

        syn_weight          : out std_logic_vector(3 downto 0);     -- synaptic weight
        syn_event           : out std_logic;                        -- synaptic event trigger
        time_ref            : out std_logic;                        -- time reference event trigger

        spike_out           : in std_logic                          -- neuron spike event output
    );
end controller;

architecture Behavioral of controller is
    -- state machine
    type states is (
        IDLE,       -- idle state
        ITRT_NRN,   -- iterate neurons
        ITRT_IBF,   -- iterate input buffer
        ITRT_SYN,   -- iterate synapses
        COMPUTE,    -- compute neuron
        UPDT_STATE, -- update neuron state
        WRITE_NRN   -- write neuron memory
    );
    signal cur_state                : states;

    -- input buffer address counter and value
    signal ibf_addr_cntr    : std_logic_vector(7 downto 0);         -- input buffer address counter
    signal ibf_val          : std_logic_vector(31 downto 0);        -- input buffer value

    -- synapse memory address counter and value
    signal syn_addr_cntr    : std_logic_vector(15 downto 0);         -- synapse memory address counter
    signal syn_val          : std_logic_vector(31 downto 0);        -- synapse memory value

    -- neuron memory address counter and value
    signal nrn_addr_cntr    : std_logic_vector(7 downto 0);         -- neuron memory address counter
    signal nrn_val          : std_logic_vector(31 downto 0);        -- neuron memory value

begin
    process(clk) is

    variable syn_idx        : integer range 0 to 7;                 -- synapse block index counter
    variable tot_syn_idx    : integer range 0 to 47;                -- total synapse index counter
    variable state_core_i   : std_logic_vector(11 downto 0);        -- core neuron state
    variable spike_out_cnt  : integer range 0 to 255;               -- spike out counter

    begin
        if rising_edge(clk) then
            -- reset state machine
            if nRst = '0' then
                cur_state <= IDLE;
                nrn_we    <= '0';
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
                        -- set BRAM address
                        nrn_addr        <= nrn_addr_cntr;
                        nrn_we          <= '0';

                        -- increment address counter
                        nrn_addr_cntr   <= std_logic_vector( unsigned(nrn_addr_cntr) + 1 );
                        ibf_addr_cntr   <= (others => '0');

                        -- load neuron parameters and state
                        param_leak_str  <= nrn_in(6 downto 0);
                        param_thr       <= nrn_in(17 downto 6);
                        state_core_i    := nrn_in(29 downto 18);
                        tot_syn_idx     := 0;
                        spike_out_cnt   := 0;

                        -- if last neuron, go to IDLE
                        if (unsigned(nrn_addr_cntr) = 48) then
                            cur_state <= IDLE;
                        else
                            cur_state <= ITRT_IBF;
                        end if;

                    when ITRT_IBF =>
                        -- set BRAM address
                        ibf_addr        <= ibf_addr_cntr;

                        -- increment address counter
                        ibf_addr_cntr   <= std_logic_vector( unsigned(ibf_addr_cntr) + 1 );

                        -- compute next neuron state
                        if (unsigned(syn_addr_cntr) /= 0 and (unsigned(syn_addr_cntr) - 1) mod 4 = 0) then
                            cur_state <= COMPUTE;
                        else
                            cur_state <= ITRT_SYN;
                        end if;

                    when ITRT_SYN =>
                        -- set BRAM address
                        syn_addr        <= syn_addr_cntr;

                        -- increment address counter
                        syn_addr_cntr   <= std_logic_vector( unsigned(syn_addr_cntr) + 1 );

                        -- for every 8th synapse, iterate the input buffer
                        if (unsigned(syn_addr_cntr) /= 0 and unsigned(syn_addr_cntr) mod 4 = 0) then
                            cur_state <= ITRT_IBF;
                        else
                            cur_state <= COMPUTE;
                        end if;

                    when WRITE_NRN =>
                        -- write neuron memory
                        nrn_we  <= '1';
                        nrn_out(31 downto 30) <= "00";
                        nrn_out(29 downto 18) <= state_core_i;
                        nrn_out(17 downto 6)  <= param_thr;
                        nrn_out(6 downto 0)   <= param_leak_str;

                        -- compute next neuron state
                        cur_state <= ITRT_NRN;

                    when COMPUTE =>
                        -- compute neuron states
                        out1 <= ibf_in;

                        -- compute next neuron state
                        state_core      <= state_core_i;
                        time_ref        <= '0';

                        if tot_syn_idx = 47 then
                            cur_state <= WRITE_NRN;
                        elsif syn_idx < 8 then
                            syn_weight  <= syn_in( (syn_idx * 4) + 3 downto (syn_idx * 4) );
                            syn_event   <= ibf_in(tot_syn_idx mod 32);
                            syn_idx     := syn_idx + 1;
                            cur_state   <= UPDT_STATE;
                        else
                            syn_idx     := 0;
                            cur_state   <= ITRT_SYN;
                        end if;

                        tot_syn_idx     := tot_syn_idx + 1;

                    when UPDT_STATE =>
                        -- count spikes
                        if spike_out = '1' then
                            spike_out_cnt := spike_out_cnt + 1;
                        end if;

                        out2 <= std_logic_vector(to_unsigned(spike_out_cnt, 32));

                        state_core_i := state_core_next;
                        cur_state <= COMPUTE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
