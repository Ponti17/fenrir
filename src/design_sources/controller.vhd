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

        out_addr            : out std_logic_vector(7 downto 0);     -- 8-bit address for output memory
        out_in              : in  std_logic_vector(31 downto 0);    -- 32-bit value for output memory
        out_out             : out std_logic_vector(31 downto 0);    -- 32-bit value from output memory
        out_we              : out std_logic;                        -- write enable for output memory

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
        ITRT_SYN,   -- iterate synapses
        WAIT_CYC,
        COMPUTE,    -- compute neuron
        UPDT_NRN,   -- update neuron using LIF model
        WRITE_NRN   -- write neuron memory
    );
    signal cur_state    : states;

    signal nrn_idx      : integer range 0 to 47 := 0;
    signal syn_idx      : integer range 0 to 47 := 0;
    signal ibf_idx      : integer range 0 to 47 := 0;
    signal acc_sum      : integer range 0 to 2048 := 0; -- accumulator for neuron potential (0 to 2^11)

begin
    process(clk) is

    variable syn_val            : integer range 0 to 15;    -- 2^4
    variable ibf_val            : integer range -1 to 1;    -- positive or negative spikes
    variable par_sum            : integer;                  -- must be high enough
    variable state_core_i       : integer;

    begin
        if rising_edge(clk) then
            if nRst = '0' then
                nrn_we      <= '0';
                nrn_idx     <= 0;
                syn_idx     <= 0;
                ibf_idx     <= 0;
                acc_sum     <= 0;
                cur_state   <= IDLE;
            else
                case cur_state is
                    when IDLE =>
                        busy    <= '0';
                        nrn_idx <= 0;
                        syn_idx <= 0;
                        ibf_idx <= 0;
                        acc_sum <= 0;
                        if data_rdy = '1' then
                            cur_state <= ITRT_NRN;
                            busy      <= '1';
                        end if;

                    when ITRT_NRN =>
                        nrn_addr <= std_logic_vector(to_unsigned(nrn_idx, 8));
                        nrn_we   <= '0';
                        out_we   <= '0';

                        syn_idx <= 0;
                        ibf_idx <= 0;
                        acc_sum <= 0;

                        cur_state <= ITRT_SYN;

                    when ITRT_SYN =>
                        syn_addr <= std_logic_vector(to_unsigned(syn_idx / 8 + nrn_idx * 6, 16));
                        ibf_addr <= std_logic_vector(to_unsigned(ibf_idx / 16, 8));

                        cur_state <= WAIT_CYC;

                    when WAIT_CYC =>
                        cur_state <= COMPUTE;

                    when COMPUTE =>
                        par_sum := 0;
                        for i in 0 to 7 loop
                            syn_val := to_integer(unsigned(syn_in(4 * i + 3 downto 4 * i)));
                            -- shitty math required to iterate over 32-bit input buffer of 2-bit values for every 8 synapses
                            ibf_val := to_integer(signed(ibf_in(i * 2 + 1 + ((ibf_idx mod 16) * 2) downto i * 2 + ((ibf_idx mod 16) * 2))));
                            par_sum := par_sum + syn_val * ibf_val;
                        end loop;
                        acc_sum <= acc_sum + par_sum;

                        if syn_idx < 47 - 8 then
                            syn_idx <= syn_idx + 8;
                            ibf_idx <= ibf_idx + 8;
                            cur_state <= ITRT_SYN;
                        else
                            cur_state <= UPDT_NRN;
                        end if;
                    
                    when UPDT_NRN =>
                        -- update neuron state
                        param_leak_str <= nrn_in(6 downto 0);
                        param_thr      <= nrn_in(18 downto 7);
                        syn_weight     <= (others => '0');
                        syn_event      <= '0';
                        time_ref       <= '1';

                        -- write back neuron state
                        state_core_i   := to_integer(signed(nrn_in(30 downto 19)));
                        state_core_i   := state_core_i + acc_sum;
                        state_core     <= std_logic_vector(to_signed(state_core_i, 12));

                        out_addr      <= std_logic_vector(to_unsigned(nrn_idx / 32, 8));

                        cur_state <= WRITE_NRN;

                    when WRITE_NRN =>
                        nrn_addr <= std_logic_vector(to_unsigned(nrn_idx, 8));
                        nrn_out(30 downto 19) <= state_core_next(11 downto 0);
                        nrn_out(18 downto 7)  <= nrn_in(18 downto 7);
                        nrn_out(6 downto 0)   <= nrn_in(6 downto 0);
                        nrn_we   <= '1';

                        out_we   <= '1';
                        out_out  <= out_in when spike_out = '0' else
                                    out_in or (std_logic_vector(to_unsigned(1, 32)) sll (nrn_idx mod 32));

                        if nrn_idx < 47 then
                            nrn_idx <= nrn_idx + 1;
                            cur_state <= ITRT_NRN;
                        else
                            cur_state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;
end Behavioral;
