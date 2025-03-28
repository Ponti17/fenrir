library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controller_tb is
end controller_tb;

architecture behavior of controller_tb is
    -- controller signals
    signal clk             : std_logic := '0';
    signal nRst            : std_logic := '1';
    signal busy            : std_logic;
    signal data_rdy        : std_logic := '0';

    signal ibf_addr        : std_logic_vector(15 downto 0);
    signal ibf_in          : std_logic_vector(31 downto 0);

    signal out_addr        : std_logic_vector(15 downto 0);
    signal out_in          : std_logic_vector(31 downto 0);

    signal syn_addr        : std_logic_vector(15 downto 0);
    signal syn_in          : std_logic_vector(31 downto 0);

    signal nrn_addr        : std_logic_vector(15 downto 0);
    signal nrn_in          : std_logic_vector(31 downto 0);

    -- memory signals
    signal ibf_we               : std_logic := '0';                 -- Write enable for memory
    signal ibf_din              : std_logic_vector(31 downto 0);    -- Data input to memory
    signal ibf_dout             : std_logic_vector(31 downto 0);    -- Data output from memory

    signal out_we               : std_logic := '0';                 -- Write enable for memory
    signal out_din              : std_logic_vector(31 downto 0);    -- Data input to memory
    signal out_dout             : std_logic_vector(31 downto 0);    -- Data output from memory

    signal syn_we               : std_logic := '0';                 -- Write enable for memory
    signal syn_din              : std_logic_vector(31 downto 0);    -- Data input to memory
    signal syn_dout             : std_logic_vector(31 downto 0);    -- Data output from memory

    signal nrn_we               : std_logic;                        -- Write enable for memory
    signal nrn_din              : std_logic_vector(31 downto 0);    -- Data input to memory
    signal nrn_dout             : std_logic_vector(31 downto 0);    -- Data output from memory

    -- lif neuron
    signal param_leak_str       : std_logic_vector(6 downto 0);     -- leakage stength parameter
    signal param_thr            : std_logic_vector(11 downto 0);    -- neuron firing threshold parameter

    signal state_core           : std_logic_vector(11 downto 0);    -- core neuron state from SRAM
    signal state_core_next      : std_logic_vector(11 downto 0);    -- next core neuron state to SRAM

    signal syn_weight           : std_logic_vector(3 downto 0);     -- synaptic weight
    signal syn_event            : std_logic;                        -- synaptic event trigger
    signal time_ref             : std_logic;                        -- time reference event trigger

    signal spike_out            : std_logic;                        -- neuron spike event output

    -- Clock period
    constant clk_period : time := 10 ns;

begin
    -- instantiate controller
    uut: entity work.controller
        generic map (
            NUM_NRN         => 64
        )
        port map (
            clk             => clk,
            nRst            => nRst,
            busy            => busy,
            data_rdy        => data_rdy,

            ibf_addr        => ibf_addr,
            ibf_in          => ibf_dout,

            out_addr        => out_addr,
            out_in          => out_dout,
            out_out         => out_din,
            out_we          => out_we,

            syn_addr        => syn_addr,
            syn_in          => syn_dout,

            nrn_addr        => nrn_addr,
            nrn_in          => nrn_dout,
            nrn_out         => nrn_din,
            nrn_we          => nrn_we,

            param_leak_str  => param_leak_str,
            param_thr       => param_thr,
            state_core      => state_core,
            state_core_next => state_core_next,
            syn_weight      => syn_weight,
            syn_event       => syn_event,
            time_ref        => time_ref,
            spike_out       => spike_out
        );

    lif_neuron: entity work.lif_neuron
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

    -- instantiate memory modules with unique names
    ibf_mem: entity work.bram_mem
        generic map (
            G_DEBUG                 => false,
            G_DEBUG_COUNTER_INIT    => 0,
            DEPTH                   => 256,
            WIDTH                   => 32,
            WIDTH_ADDR              => 16,
            FILENAME                => "data/ibf_init.data"
        )
        port map (
            clk         => clk,
            we          => ibf_we,
            addr        => ibf_addr,
            din         => ibf_din,
            dout        => ibf_dout
        );

    out_mem: entity work.bram_mem
        generic map (
            G_DEBUG                 => false,
            G_DEBUG_COUNTER_INIT    => 0,
            DEPTH                   => 256,
            WIDTH                   => 32,
            WIDTH_ADDR              => 16,
            FILENAME                => "data/out_init.data"
        )
        port map (
            clk         => clk,
            we          => out_we,
            addr        => out_addr,
            din         => out_din,
            dout        => out_dout
        );

    syn_mem: entity work.bram_mem
        generic map (
            G_DEBUG                 => false,
            G_DEBUG_COUNTER_INIT    => 0,
            DEPTH                   => 65536,
            WIDTH                   => 32,
            WIDTH_ADDR              => 16,
            FILENAME                => "data/syn_init.data"
        )
        port map (
            clk         => clk,
            we          => syn_we,
            addr        => syn_addr,
            din         => syn_din,
            dout        => syn_dout
        );

    nrn_mem: entity work.bram_mem
        generic map (
            G_DEBUG                 => false,
            G_DEBUG_COUNTER_INIT    => 0,
            DEPTH                   => 256,
            WIDTH                   => 32,
            WIDTH_ADDR              => 16,
            FILENAME                => "data/nrn_init.data"
        )
        port map (
            clk         => clk,
            we          => nrn_we,
            addr        => nrn_addr,
            din         => nrn_din,
            dout        => nrn_dout
        );

    -- Generate clock signal
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period / 2;
        clk <= '1';
        wait for clk_period / 2;
    end process;

    -- Stimulus process
    stimulus: process
    begin
        -- Reset the DUT
        nRst <= '0';
        wait for clk_period * 2;
        nRst <= '1';
        wait for clk_period;

        -- Test 1: When data is ready, controller should go into READ state
        data_rdy <= '1';
        wait for clk_period;

        -- Simulate reading and incrementing address
        for i in 0 to 1800 loop
            data_rdy <= '0';
            wait for clk_period;
        end loop;

        data_rdy <= '1';
        wait for clk_period;

        -- Simulate reading and incrementing address
        for i in 0 to 255 loop
            data_rdy <= '0';
            wait for clk_period;
        end loop;

        wait;
    end process;

end behavior;
