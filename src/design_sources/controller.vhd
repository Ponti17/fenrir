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
*/

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controller is
    port (

        clk             : in std_logic;
        ready           : out std_logic; -- ready signal for data

        -- Data
        input_vector    : in std_logic_vector(15 downto 0); -- 16-bit input
        input_select    : out std_logic_vector(3 downto 0); -- 4-bit selector for input
        data_rdy        : in std_logic; -- data ready signal

        -- neuron and synapse 
        neuron_address  : out std_logic_vector(7 downto 0); -- 8-bit address for neuron
        neuron_input    : in std_logic_vector(31 downto 0); -- 32-bit input for neuron
        neuron_we       : out std_logic; -- write enable for neuron
        neuron_update   : out std_logic_vector(31 downto 0); -- 32-bit update for neuron

        synapse_address : out std_logic_vector(7 downto 0); -- 8-bit address for synapse
        synapse_in      : in std_logic_vector(31 downto 0); -- 32-bit input for synapse

        -- signals for active neuron
        param_leak_str  : out std_logic_vector(6 downto 0); -- leakage stength parameter
        param_thr       : out std_logic_vector(11 downto 0); -- neuron firing threshold parameter
        state_core      : out std_logic_vector(11 downto 0); -- core neuron state from SRAM
        syn_weight      : out std_logic_vector(1 downto 0); -- synaptic weight
        syn_event       : out std_logic; -- synaptic event trigger
        
        state_core_next : in std_logic_vector(11 downto 0); -- next core neuron state to SRAM
        spike_out       : in std_logic -- neuron spike event output

    );
end controller;

architecture Behavioral of controller is
    signal synapse_counter          : integer := 0;
    signal neuron_counter           : integer := 0;
    signal input_row_counter        : integer := 0;

    type main_states is (
        IDLE,
        READ_REQUEST,
        WRITE_REQUEST,
        UPDATE,
        COMPUTE
    );
    type read_request_substates is (
        READ_NEURON,
        READ_SYNAPSE,
        READ_BOTH
    );

    signal MAIN_STATE               : main_states := IDLE;
    signal REQUEST_STATE            : read_request_substates := READ_BOTH;
    
begin

    process (clk)

        variable temp_neuron        : std_logic_vector(31 downto 0);
        
    begin
        if rising_edge(clk) then

            case MAIN_STATE is

                when IDLE =>
                    
                    if data_rdy = '1' then
                        -- data is ready, flip the ready signal and start getting neuron and synapse
                        ready       <= '0';
                        MAIN_STATE  <= READ_REQUEST;

                    else 

                        ready       <= '1';

                    end if;

                when READ_REQUEST => 

                    -- for reading neuron and synapses
                    -- when last synapse is reached we want to read neuron and synapse. Otherwise we want to read only synapse

                    case REQUEST_STATE is

                        when READ_NEURON =>

                            -- read neuron
                            -- convert neuron counter to 8-bit address
                            neuron_we       <= '0';
                            neuron_address  <= std_logic_vector(to_unsigned(neuron_counter, 8));
                            MAIN_STATE      <= UPDATE;

                        when READ_SYNAPSE =>

                            -- read synapse
                            if (synapse_counter > 15 and synapse_counter < 32) then

                                -- multiply neuron counter by 3 and add 1
                                synapse_address <= std_logic_vector(to_unsigned(neuron_counter * 3 + 1, 8));

                            else

                                -- multiply neuron counter by 3 and add 2
                                synapse_address <= std_logic_vector(to_unsigned(neuron_counter * 3 + 2, 8));

                            end if;

                            MAIN_STATE      <= COMPUTE;

                        when READ_BOTH =>

                            -- read both
                            -- multiply neuron counter by 3
                            synapse_address     <= std_logic_vector(to_unsigned(neuron_counter * 3, 8));
                            -- same address for neuron
                            neuron_address      <= std_logic_vector(to_unsigned(neuron_counter, 8));

                    end case;

                when WRITE_REQUEST =>

                    -- for updating neuron
                    neuron_we           <= '1';
                    neuron_update       <= temp_neuron;

                    MAIN_STATE          <= READ_REQUEST;
                    REQUEST_STATE       <= READ_BOTH;

                when UPDATE => 

                    -- update internal signals and variables 
                    temp_neuron := neuron_input;

                when COMPUTE => 
                    -- main loop
                    -- start updating the neuron signals from the 32 bit word from neuron bram (neuron_input)

                    param_leak_str      <= neuron_input(30 downto 24);
                    param_thr           <= neuron_input(23 downto 12);
                    state_core          <= temp_neuron(11 downto 0);

                    -- we must update the synapse weight. Since we are reading synapses as 32 bit words, we need to extract the weight from the word
                    -- each synapse_in word contains 16 weights. We use the counter signal to index the 2 bit weight
                    syn_weight          <= synapse_in(2 * synapse_counter + 1 downto 2 * synapse_counter);

                    -- pass the input bit from the input vector. Indexed by the synapse counter
                    syn_event           <= input_vector(synapse_counter - (input_row_counter * 16));

                    -- increment the synapse counter
                    synapse_counter     <= synapse_counter + 1;

                    -- read the state core from the state_core_next signal
                    temp_neuron(11 downto 0) := state_core_next;

                    -- check if the neuron has spiked
                    if spike_out = '1' then

                        -- if the neuron has spiked we want to do something. 
                        -- Maybe just go to next neuron and store a spike somewhere ? todo!!!
                        synapse_counter <= 48;

                    end if;

                    -- check synapse counter
                    if synapse_counter = 16 or synapse_counter = 32 then

                        -- we need to read the following 16 weights and increment the row counter. 
                        MAIN_STATE          <= READ_REQUEST;
                        REQUEST_STATE       <= READ_SYNAPSE;
                        input_row_counter   <= input_row_counter + 1;
                        -- update the input select port signal
                        input_select        <= std_logic_vector(to_unsigned(input_row_counter, 4));
                        
                    elsif synapse_counter = 48 then 

                        -- next neuron
                        synapse_counter     <= 0;
                        neuron_counter      <= neuron_counter + 1;
                        input_row_counter   <= 0;
                        MAIN_STATE          <= WRITE_REQUEST;
        
                    end if;

                when others => 

                    MAIN_STATE              <= IDLE;

            end case;
        end if;
    end process;

end Behavioral;
