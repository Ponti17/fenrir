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

    -- memory address counters
    signal ibf_addr_cntr    : std_logic_vector(7 downto 0);         -- input buffer
    signal syn_addr_cntr    : std_logic_vector(15 downto 0);        -- synapses
    signal nrn_addr_cntr    : std_logic_vector(7 downto 0);         -- neurons

begin
    process(clk) is

    variable syn_idx        : integer range 0 to 7;                 -- synapse block index counter
    variable tot_syn_idx    : integer range 0 to 47;                -- total synapse index counter
    variable state_core_i   : std_logic_vector(11 downto 0);        -- core neuron state
    variable spike_out_cnt  : integer range 0 to 255;               -- spike out counter

    begin
        if rising_edge(clk) then
            ----------------------------------------------------------------------
            -- RESET
            -- Address counters are forcibly reset and state is set to IDLE
            ----------------------------------------------------------------------
            if nRst = '0' then
                nrn_we        <= '0';
                ibf_addr_cntr <= (others => '0');
                syn_addr_cntr <= (others => '0');
                nrn_addr_cntr <= (others => '0');
                cur_state     <= IDLE;
            else
                case cur_state is
                    ----------------------------------------------------------------------
                    -- STATE             : IDLE
                    -- PREDECESSOR STATES: RESET, ITRT_NRN
                    --
                    -- Description:
                    -- Address counters are reset. Awaiting data to start iterating.
                    --
                    -- Transition Conditions:
                    --  -> ITRT_NRN: Input buffer is ready and data_rdy is high.
                    ----------------------------------------------------------------------
                    when IDLE =>
                        -- wait for data_rdy signal
                        busy <= '0';
                        -- reset address counters
                        ibf_addr_cntr <= (others => '0');
                        syn_addr_cntr <= (others => '0');
                        nrn_addr_cntr <= (others => '0');
                        -- start reading if data is ready
                        if data_rdy = '1' then
                            cur_state <= ITRT_NRN;
                            busy <= '1';
                        end if;

                    ----------------------------------------------------------------------
                    -- STATE             : ITRT_NRN
                    -- PREDECESSOR STATES: IDLE, WRITE_NRN
                    --
                    -- Description:
                    -- The neuron memory address is read and incremented.
                    -- The input buffer address is reset to 0.
                    -- 
                    -- Neuron parameters are loaded into the LIF logic, and the potential
                    -- is stored in a process variable. The syn_idx counter is reset to 0.
                    --
                    -- Transition Conditions:
                    --  -> IDLE    : If the last neuron is reached, go to IDLE.
                    --  -> ITRT_IBF: Otherwise, the state is set to ITRT_IBF.
                    ----------------------------------------------------------------------
                    when ITRT_NRN =>
                        nrn_addr        <= nrn_addr_cntr;
                        nrn_we          <= '0';

                        nrn_addr_cntr   <= std_logic_vector( unsigned(nrn_addr_cntr) + 1 );
                        ibf_addr_cntr   <= (others => '0');

                        -- load neuron parameters and state
                        param_leak_str  <= nrn_in(6 downto 0);
                        param_thr       <= nrn_in(17 downto 6);
                        state_core_i    := nrn_in(29 downto 18);
                        tot_syn_idx     := 0;

                        -- if last neuron, go to IDLE
                        if (unsigned(nrn_addr_cntr) = 48) then
                            cur_state <= IDLE;
                        else
                            cur_state <= ITRT_IBF;
                        end if;

                    ----------------------------------------------------------------------
                    -- STATE             : ITRT_IBF
                    -- PREDECESSOR STATES: ITRT_NRN, ITRT_SYN
                    --
                    -- Description:
                    -- The input buffer address is read and incremented. The buffer
                    -- contains 16 2-bit values for negative, positive and no spike.
                    --
                    -- For every 16 synapses (2 addresses), the ITRT_SYN state will switch
                    -- to ITRT_IBF state to iterate the input buffer.
                    -- 
                    -- Transition Conditions:
                    --  -> COMPUTE : If we came from ITRT_SYN (syn_addr is a multiple of 2).
                    --  -> ITRT_SYN: If we are iterating for the first time.
                    ----------------------------------------------------------------------
                    when ITRT_IBF =>
                        ibf_addr        <= ibf_addr_cntr;
                        ibf_addr_cntr   <= std_logic_vector( unsigned(ibf_addr_cntr) + 1 );

                        if (unsigned(syn_addr_cntr) /= 0 and (unsigned(syn_addr_cntr) - 1) mod 2 = 0) then
                            cur_state <= COMPUTE;
                        else
                            cur_state <= ITRT_SYN;
                        end if;

                    ----------------------------------------------------------------------
                    -- STATE             : ITRT_SYN
                    -- PREDECESSOR STATES: ITRT_IBF, COMPUTE
                    --
                    -- Description:
                    -- The synapse memory address is read and incremented.
                    -- For every 16th synapse (2 addresses), we switch to ITRT_IBF state,
                    -- to load the next 32 bits of input buffer data.
                    -- 
                    -- Transition Conditions:
                    --  -> ITRT_IBF: Every 16th synapse.
                    --  -> COMPUTE : Otherwise, compute the neuron state.
                    ----------------------------------------------------------------------
                    when ITRT_SYN =>
                        syn_addr        <= syn_addr_cntr;
                        syn_addr_cntr   <= std_logic_vector( unsigned(syn_addr_cntr) + 1 );

                        if (unsigned(syn_addr_cntr) /= 0 and unsigned(syn_addr_cntr) mod 2 = 0) then
                            cur_state <= ITRT_IBF;
                        else
                            cur_state <= COMPUTE;
                        end if;

                    ----------------------------------------------------------------------
                    -- STATE             : COMPUTE
                    -- PREDECESSOR STATES: ITRT_IBF, ITRT_SYN, UPDT_STATE
                    --
                    -- Description:
                    -- The synapse memory address is read and incremented.
                    -- For every 16th synapse (2 addresses), we switch to ITRT_IBF state,
                    -- to load the next 32 bits of input buffer data.
                    -- 
                    -- Transition Conditions:
                    --  -> ITRT_IBF: Every 16th synapse.
                    --  -> COMPUTE : Otherwise, compute the neuron state.
                    ----------------------------------------------------------------------
                    when COMPUTE =>
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

                        when WRITE_NRN =>
                        -- write neuron memory
                        nrn_we  <= '1';
                        nrn_out(31 downto 30) <= "00";
                        nrn_out(29 downto 18) <= state_core_i;
                        nrn_out(17 downto 6)  <= param_thr;
                        nrn_out(6 downto 0)   <= param_leak_str;

                        -- compute next neuron state
                        cur_state <= ITRT_NRN;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
