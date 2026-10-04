// Two-port, bidirectional Ethernet filter. Port 0 RX is forwarded to port 1 TX;
// port 1 RX is forwarded to port 0 TX. PHY management/autonegotiation is external.
module gowin_ethernet_filter_top #(
    parameter signed [23:0] MODEL_W_BIAS      = 24'sd0,
    parameter signed [23:0] MODEL_W_MULTICAST = 24'sd0,
    parameter signed [23:0] MODEL_W_ARP       = 24'sd0,
    parameter signed [23:0] MODEL_W_IPV4      = 24'sd0,
    parameter signed [23:0] MODEL_W_IPV6      = 24'sd0,
    parameter signed [23:0] MODEL_W_VLAN      = 24'sd0,
    parameter signed [23:0] MODEL_W_TCP       = 24'sd0,
    parameter signed [23:0] MODEL_W_UDP       = 24'sd0,
    parameter signed [23:0] MODEL_W_PORT23    = 24'sd256,
    parameter signed [23:0] MODEL_W_UNKNOWN   = 24'sd0,
    parameter signed [23:0] MODEL_THRESHOLD   = 24'sd128
) (
    input  wire        ref_clk_50m,
    input  wire        rst_n,
    input  wire        phy0_link_100fd,
    input  wire        phy1_link_100fd,
    input  wire [1:0]  phy0_rxd,
    input  wire        phy0_crs_dv,
    input  wire        phy0_rxer,
    output wire [1:0]  phy0_txd,
    output wire        phy0_txen,
    output wire        blocked_p0_to_p1_pulse,
    input  wire [1:0]  phy1_rxd,
    input  wire        phy1_crs_dv,
    input  wire        phy1_rxer,
    output wire [1:0]  phy1_txd,
    output wire        phy1_txen,
    output wire        blocked_p1_to_p0_pulse,
    output wire        phy0_reset_n,
    output wire        phy1_reset_n
);
    wire [31:0] p0_to_p1_accepted;
    wire [31:0] p0_to_p1_blocked;
    wire [31:0] p0_to_p1_bad;
    wire [31:0] p0_to_p1_no_buffer;
    wire [31:0] p1_to_p0_accepted;
    wire [31:0] p1_to_p0_blocked;
    wire [31:0] p1_to_p0_bad;
    wire [31:0] p1_to_p0_no_buffer;

    // Hold both PHYs in reset whenever FPGA/system reset is asserted.
    assign phy0_reset_n = rst_n;
    assign phy1_reset_n = rst_n;

    rmii_filter_channel #(
        .W_BIAS(MODEL_W_BIAS), .W_MULTICAST(MODEL_W_MULTICAST),
        .W_ARP(MODEL_W_ARP), .W_IPV4(MODEL_W_IPV4), .W_IPV6(MODEL_W_IPV6),
        .W_VLAN(MODEL_W_VLAN), .W_TCP(MODEL_W_TCP), .W_UDP(MODEL_W_UDP),
        .W_PORT23(MODEL_W_PORT23), .W_UNKNOWN(MODEL_W_UNKNOWN),
        .THRESHOLD(MODEL_THRESHOLD)
    ) p0_to_p1 (
        .clk_50m(ref_clk_50m), .rst_n(rst_n), .output_link_100fd(phy1_link_100fd),
        .rx_data(phy0_rxd), .rx_dv(phy0_crs_dv), .rx_er(phy0_rxer),
        .tx_data(phy1_txd), .tx_en(phy1_txen), .blocked_pulse(blocked_p0_to_p1_pulse),
        .accepted_frames(p0_to_p1_accepted), .blocked_frames(p0_to_p1_blocked),
        .bad_frames(p0_to_p1_bad), .no_buffer_frames(p0_to_p1_no_buffer)
    );

    rmii_filter_channel #(
        .W_BIAS(MODEL_W_BIAS), .W_MULTICAST(MODEL_W_MULTICAST),
        .W_ARP(MODEL_W_ARP), .W_IPV4(MODEL_W_IPV4), .W_IPV6(MODEL_W_IPV6),
        .W_VLAN(MODEL_W_VLAN), .W_TCP(MODEL_W_TCP), .W_UDP(MODEL_W_UDP),
        .W_PORT23(MODEL_W_PORT23), .W_UNKNOWN(MODEL_W_UNKNOWN),
        .THRESHOLD(MODEL_THRESHOLD)
    ) p1_to_p0 (
        .clk_50m(ref_clk_50m), .rst_n(rst_n), .output_link_100fd(phy0_link_100fd),
        .rx_data(phy1_rxd), .rx_dv(phy1_crs_dv), .rx_er(phy1_rxer),
        .tx_data(phy0_txd), .tx_en(phy0_txen), .blocked_pulse(blocked_p1_to_p0_pulse),
        .accepted_frames(p1_to_p0_accepted), .blocked_frames(p1_to_p0_blocked),
        .bad_frames(p1_to_p0_bad), .no_buffer_frames(p1_to_p0_no_buffer)
    );
endmodule
