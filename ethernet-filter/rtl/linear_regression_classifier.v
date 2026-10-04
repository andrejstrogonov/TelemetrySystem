// Fixed-point linear score classifier for a small, parsed Ethernet feature vector.
// Coefficients are fitted offline and become constants in the Gowin bitstream.
module linear_regression_classifier #(
    parameter signed [23:0] W_BIAS      = 24'sd0,
    parameter signed [23:0] W_MULTICAST = 24'sd0,
    parameter signed [23:0] W_ARP       = 24'sd0,
    parameter signed [23:0] W_IPV4      = 24'sd0,
    parameter signed [23:0] W_IPV6      = 24'sd0,
    parameter signed [23:0] W_VLAN      = 24'sd0,
    parameter signed [23:0] W_TCP       = 24'sd0,
    parameter signed [23:0] W_UDP       = 24'sd0,
    parameter signed [23:0] W_PORT23    = 24'sd256,
    parameter signed [23:0] W_UNKNOWN   = 24'sd0,
    parameter signed [23:0] THRESHOLD   = 24'sd128
) (
    input  wire [8:0]         features,
    output wire signed [23:0] score,
    output wire               unwanted
);
    // features[0..8] = multicast, ARP, IPv4, IPv6, VLAN, TCP, UDP,
    //                  IPv4 TCP/UDP destination port 23, unknown EtherType.
    wire signed [23:0] t0 = features[0] ? W_MULTICAST : 24'sd0;
    wire signed [23:0] t1 = features[1] ? W_ARP       : 24'sd0;
    wire signed [23:0] t2 = features[2] ? W_IPV4      : 24'sd0;
    wire signed [23:0] t3 = features[3] ? W_IPV6      : 24'sd0;
    wire signed [23:0] t4 = features[4] ? W_VLAN      : 24'sd0;
    wire signed [23:0] t5 = features[5] ? W_TCP       : 24'sd0;
    wire signed [23:0] t6 = features[6] ? W_UDP       : 24'sd0;
    wire signed [23:0] t7 = features[7] ? W_PORT23    : 24'sd0;
    wire signed [23:0] t8 = features[8] ? W_UNKNOWN   : 24'sd0;

    assign score = W_BIAS + t0 + t1 + t2 + t3 + t4 + t5 + t6 + t7 + t8;
    assign unwanted = (score >= THRESHOLD);
endmodule
