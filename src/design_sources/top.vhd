/*
---------------------------------------------------------------------------------------------------
    Aarhus University (AU, Denmark)
---------------------------------------------------------------------------------------------------

    File: top.vhd
    Description: Top module of 8x6 neural network.

    Author(s):
        - A. Pedersen, Aarhus University
        - A. Cherencq, Aarhus University

---------------------------------------------------------------------------------------------------
*/

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity snn_top is
    port (
        clk             : in std_logic;
        input_vector    : in std_logic_vector(15 downto 0);
        data_rdy        : in std_logic;
        spike_out       : out std_logic
    );
end snn_top;

architecture Structural of snn_top is
    -- Controller
    signal ready           : std_logic;
    signal input_select    : std_logic_vector(3 downto 0);

    signal input_vector    : in std_logic_vector(15 downto 0);
    signal input_select    : out std_logic_vector(3 downto 0);
    signal data_rdy        : in std_logic;
    signal neuron_address  : out std_logic_vector(7 downto 0);
    signal neuron_input    : in std_logic_vector(31 downto 0);
    signal neuron_we       : out std_logic;
    signal neuron_update   : out std_logic_vector(31 downto 0);

    signal synapse_address : out std_logic_vector(7 downto 0);
    signal synapse_in      : in std_logic_vector(31 downto 0);

    signal param_leak_str  : out std_logic_vector(6 downto 0);
    signal param_thr       : out std_logic_vector(11 downto 0);
    signal state_core      : out std_logic_vector(11 downto 0);
    signal syn_weight      : out std_logic_vector(1 downto 0);
    signal syn_event       : out std_logic;
    
    signal state_core_next : in std_logic_vector(11 downto 0);
    signal spike_out       : in std_logic

    -- Neuron Memory
    signal neuron_address  : std_logic_vector(7 downto 0);
    signal neuron_input    : std_logic_vector(31 downto 0);
    signal neuron_we       : std_logic;
    signal neuron_update   : std_logic_vector(31 downto 0);

    -- Synapse Memory
    signal synapse_address  : std_logic_vector(7 downto 0);
    signal synapse_input    : std_logic_vector(31 downto 0);
    signal synapse_we       : std_logic;
    signal synapse_update   : std_logic_vector(31 downto 0);

    -- LIF Neuron
    signal param_leak_str  : std_logic_vector(6 downto 0);
    signal param_thr       : std_logic_vector(11 downto 0);
    signal state_core      : std_logic_vector(11 downto 0);
    signal syn_weight      : std_logic_vector(3 downto 0);
    signal syn_event       : std_logic;
    signal time_ref        : std_logic;
    signal state_core_next : std_logic_vector(11 downto 0);

begin

    -- Instantiate Neuron Memory
    MEMORY_INST : entity work.neuron_memory
        port map (
            clk  => clk,
            we   => neuron_we,
            addr => neuron_address,
            din  => neuron_update,
            dout => neuron_input
        );

    -- Instantiate Synapse Memory
    MEMORY_INST : entity work.synapse_memory
        port map (
            clk  => clk,
            we   => neuron_we,
            addr => neuron_address,
            din  => neuron_update,
            dout => neuron_input
        );

    -- Instantiate Controller
    CONTROLLER_INST : entity work.controller
        port map (
            clk             => clk,
            ready           => ready,
            input_vector    => input_vector,
            input_select    => input_select,
            data_rdy        => data_rdy,
            neuron_address  => neuron_address,
            neuron_input    => neuron_input,
            neuron_we       => neuron_we,
            neuron_update   => neuron_update,
            synapse_address => synapse_address,
            synapse_in      => synapse_input,
            param_leak_str  => param_leak_str,
            param_thr       => param_thr,
            state_core      => state_core,
            syn_weight      => syn_weight,
            syn_event       => syn_event,
            state_core_next => state_core_next,
            spike_out       => spike_out
        );

    -- Instantiate LIF Neuron
    LIF_NEURON_INST : entity work.lif_neuron
        port map (
            param_leak_str  => param_leak_str,
            param_thr       => param_thr,
            state_core      => state_core,
            state_core_next => state_core_next,
            syn_weight      => syn_weight,
            syn_event       => syn_event,
            time_ref        => time_ref,
            spike_out       => spike_out
        );

end Structural;
