// Store-and-forward RMII channel, intended for 100BASE-TX full-duplex.
// Captures two dibits per RMII clock, stores two complete frames, validates
// preamble/length/FCS, scores header features, then forwards the original bytes.
module rmii_filter_channel #(
    parameter [11:0] MAX_FRAME_BYTES = 12'd1530, // preamble/SFD + tagged frame/FCS
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
    input  wire        clk_50m,
    input  wire        rst_n,
    input  wire        output_link_100fd,
    input  wire [1:0]  rx_data,
    input  wire        rx_dv,
    input  wire        rx_er,
    output reg  [1:0]  tx_data,
    output reg         tx_en,
    output reg         blocked_pulse,
    output reg  [31:0] accepted_frames,
    output reg  [31:0] blocked_frames,
    output reg  [31:0] bad_frames,
    output reg  [31:0] no_buffer_frames
);
    localparam [1:0] BANK_FREE     = 2'd0;
    localparam [1:0] BANK_FILLING  = 2'd1;
    localparam [1:0] BANK_READY    = 2'd2;
    localparam [1:0] BANK_SENDING  = 2'd3;
    localparam [1:0] TX_IDLE       = 2'd0;
    localparam [1:0] TX_PREFETCH   = 2'd1;
    localparam [1:0] TX_SEND       = 2'd2;
    localparam [1:0] TX_DRAIN      = 2'd3;
    localparam [11:0] MIN_FRAME_BYTES = 12'd72; // preamble/SFD + 64-byte Ethernet frame
    localparam [11:0] MAX_FRAME_LIMIT = MAX_FRAME_BYTES;
    localparam [31:0] ETH_CRC_RESIDUE = 32'hDEBB20E3;
    localparam [31:0] ETH_CRC_POLY = 32'hEDB88320;

    reg [7:0] frame_ram [0:(2 * MAX_FRAME_BYTES) - 1];
    reg [11:0] frame_length_0;
    reg [11:0] frame_length_1;
    reg [15:0] enqueue_sequence;
    reg [15:0] frame_sequence_0;
    reg [15:0] frame_sequence_1;
    reg [1:0] bank_state_0;
    reg [1:0] bank_state_1;

    reg rx_active;
    reg rx_drop;
    reg rx_bad;
    reg rx_overflow;
    reg rx_bank;
    reg [1:0] rx_pair_count;
    reg [7:0] rx_shift;
    reg [11:0] rx_length;
    reg [31:0] rx_crc;
    reg [8:0] rx_features;

    reg [7:0] ethertype_high;
    reg vlan_present;
    reg ipv4_packet;
    reg protocol_tcp;
    reg protocol_udp;
    reg [7:0] l3_offset;
    reg [7:0] ip_header_bytes;
    reg [7:0] destination_port_high;

    reg [1:0] tx_state;
    reg tx_bank;
    reg [11:0] tx_length;
    reg [11:0] tx_index;
    reg [1:0] tx_pair_count;
    reg [7:0] tx_byte;
    reg [5:0] tx_ifg_count;

    wire rx_free_0 = (bank_state_0 == BANK_FREE);
    wire rx_free_1 = (bank_state_1 == BANK_FREE);
    wire rx_free_available = rx_free_0 || rx_free_1;
    wire rx_selected_bank = rx_free_0 ? 1'b0 : 1'b1;
    wire [7:0] rx_completed_byte = {rx_data, rx_shift[5:0]};
    wire [10:0] ethernet_byte_index = rx_length[10:0] - 11'd8;
    wire bank_0_is_older = ($signed(frame_sequence_0 - frame_sequence_1) < 0);
    wire tx_select_bank_0 = (bank_state_0 == BANK_READY) &&
        ((bank_state_1 != BANK_READY) || bank_0_is_older);

    wire tx_ram_read_enable = (tx_state == TX_PREFETCH) ||
        ((tx_state == TX_SEND) && (tx_pair_count == 2'd3) &&
         ((tx_index + 12'd1) < tx_length));
    wire [11:0] tx_ram_read_address =
        (tx_bank ? MAX_FRAME_LIMIT : 12'd0) + tx_index +
        ((tx_state == TX_SEND) ? 12'd1 : 12'd0);
    wire signed [23:0] classifier_score;
    wire classifier_unwanted;

    linear_regression_classifier #(
        .W_BIAS(W_BIAS), .W_MULTICAST(W_MULTICAST), .W_ARP(W_ARP),
        .W_IPV4(W_IPV4), .W_IPV6(W_IPV6), .W_VLAN(W_VLAN),
        .W_TCP(W_TCP), .W_UDP(W_UDP), .W_PORT23(W_PORT23),
        .W_UNKNOWN(W_UNKNOWN), .THRESHOLD(THRESHOLD)
    ) classifier (
        .features(rx_features), .score(classifier_score), .unwanted(classifier_unwanted)
    );

    function [31:0] crc32_ethernet_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [31:0] crc_work;
        begin
            crc_work = crc_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (crc_work[0] ^ data_in[bit_index])
                    crc_work = (crc_work >> 1) ^ ETH_CRC_POLY;
                else
                    crc_work = crc_work >> 1;
            end
            crc32_ethernet_byte = crc_work;
        end
    endfunction

    // Synchronous read port for Gowin block SRAM inference. RX only writes a
    // bank marked FILLING; TX only reads a bank marked SENDING.
    always @(posedge clk_50m) begin
        if (tx_ram_read_enable)
            tx_byte <= frame_ram[tx_ram_read_address];
    end

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            rx_active <= 1'b0;
            rx_drop <= 1'b0;
            rx_bad <= 1'b0;
            rx_overflow <= 1'b0;
            rx_bank <= 1'b0;
            rx_pair_count <= 2'd0;
            rx_shift <= 8'd0;
            rx_length <= 12'd0;
            rx_crc <= 32'hFFFFFFFF;
            rx_features <= 9'd0;
            ethertype_high <= 8'd0;
            vlan_present <= 1'b0;
            ipv4_packet <= 1'b0;
            protocol_tcp <= 1'b0;
            protocol_udp <= 1'b0;
            l3_offset <= 8'd14;
            ip_header_bytes <= 8'd20;
            destination_port_high <= 8'd0;
            frame_length_0 <= 12'd0;
            frame_length_1 <= 12'd0;
            enqueue_sequence <= 16'd0;
            frame_sequence_0 <= 16'd0;
            frame_sequence_1 <= 16'd0;
            bank_state_0 <= BANK_FREE;
            bank_state_1 <= BANK_FREE;
            tx_state <= TX_IDLE;
            tx_bank <= 1'b0;
            tx_length <= 12'd0;
            tx_index <= 12'd0;
            tx_pair_count <= 2'd0;
            tx_ifg_count <= 6'd0;
            tx_data <= 2'b00;
            tx_en <= 1'b0;
            blocked_pulse <= 1'b0;
            accepted_frames <= 32'd0;
            blocked_frames <= 32'd0;
            bad_frames <= 32'd0;
            no_buffer_frames <= 32'd0;
        end else begin
            blocked_pulse <= 1'b0;
            // Start and collect the incoming RMII stream. LAN8742A RMII is
            // expected to present the translated preamble/SFD followed by DA..FCS.
            if (!rx_active && rx_dv) begin
                rx_active <= 1'b1;
                rx_drop <= !rx_free_available;
                rx_bad <= rx_er;
                rx_overflow <= 1'b0;
                rx_bank <= rx_selected_bank;
                rx_pair_count <= 2'd0;
                rx_shift <= 8'd0;
                rx_length <= 12'd0;
                rx_crc <= 32'hFFFFFFFF;
                rx_features <= 9'd0;
                ethertype_high <= 8'd0;
                vlan_present <= 1'b0;
                ipv4_packet <= 1'b0;
                protocol_tcp <= 1'b0;
                protocol_udp <= 1'b0;
                l3_offset <= 8'd14;
                ip_header_bytes <= 8'd20;
                destination_port_high <= 8'd0;
                if (rx_free_available) begin
                    if (rx_selected_bank == 1'b0)
                        bank_state_0 <= BANK_FILLING;
                    else
                        bank_state_1 <= BANK_FILLING;
                end
            end

            if (rx_dv) begin
                if (rx_er)
                    rx_bad <= 1'b1;

                case (rx_pair_count)
                    2'd0: begin
                        rx_shift[1:0] <= rx_data;
                        rx_pair_count <= 2'd1;
                    end
                    2'd1: begin
                        rx_shift[3:2] <= rx_data;
                        rx_pair_count <= 2'd2;
                    end
                    2'd2: begin
                        rx_shift[5:4] <= rx_data;
                        rx_pair_count <= 2'd3;
                    end
                    default: begin
                        rx_pair_count <= 2'd0;
                        rx_shift[7:6] <= rx_data;

                        if (!rx_drop && (rx_length < MAX_FRAME_LIMIT))
                            frame_ram[(rx_bank ? MAX_FRAME_BYTES : 0) + rx_length] <= rx_completed_byte;

                        if (rx_length < (MAX_FRAME_LIMIT + 12'd1))
                            rx_length <= rx_length + 12'd1;
                        else
                            rx_overflow <= 1'b1;

                        if (rx_length >= 12'd8)
                            rx_crc <= crc32_ethernet_byte(rx_crc, rx_completed_byte);

                        if (rx_length < 12'd8) begin
                            if ((rx_length < 12'd7 && rx_completed_byte != 8'h55) ||
                                (rx_length == 12'd7 && rx_completed_byte != 8'hD5))
                                rx_bad <= 1'b1;
                        end else begin
                            if (ethernet_byte_index == 11'd0)
                                rx_features[0] <= rx_completed_byte[0];

                            if (ethernet_byte_index == 11'd12)
                                ethertype_high <= rx_completed_byte;

                            if (ethernet_byte_index == 11'd13) begin
                                if (({ethertype_high, rx_completed_byte} == 16'h8100) ||
                                    ({ethertype_high, rx_completed_byte} == 16'h88A8)) begin
                                    vlan_present <= 1'b1;
                                    rx_features[4] <= 1'b1;
                                    l3_offset <= 8'd18;
                                end else if ({ethertype_high, rx_completed_byte} == 16'h0806) begin
                                    rx_features[1] <= 1'b1;
                                end else if ({ethertype_high, rx_completed_byte} == 16'h0800) begin
                                    rx_features[2] <= 1'b1;
                                    ipv4_packet <= 1'b1;
                                end else if ({ethertype_high, rx_completed_byte} == 16'h86DD) begin
                                    rx_features[3] <= 1'b1;
                                end else begin
                                    rx_features[8] <= 1'b1;
                                end
                            end

                            if (vlan_present && (ethernet_byte_index == 11'd16))
                                ethertype_high <= rx_completed_byte;

                            if (vlan_present && (ethernet_byte_index == 11'd17)) begin
                                if ({ethertype_high, rx_completed_byte} == 16'h0806) begin
                                    rx_features[1] <= 1'b1;
                                end else if ({ethertype_high, rx_completed_byte} == 16'h0800) begin
                                    rx_features[2] <= 1'b1;
                                    ipv4_packet <= 1'b1;
                                end else if ({ethertype_high, rx_completed_byte} == 16'h86DD) begin
                                    rx_features[3] <= 1'b1;
                                end else begin
                                    rx_features[8] <= 1'b1;
                                end
                            end

                            if (ipv4_packet && (ethernet_byte_index == l3_offset))
                                ip_header_bytes <= {rx_completed_byte[3:0], 2'b00};

                            if (ipv4_packet && (ethernet_byte_index == (l3_offset + 8'd9))) begin
                                protocol_tcp <= (rx_completed_byte == 8'd6);
                                protocol_udp <= (rx_completed_byte == 8'd17);
                                if (rx_completed_byte == 8'd6)
                                    rx_features[5] <= 1'b1;
                                if (rx_completed_byte == 8'd17)
                                    rx_features[6] <= 1'b1;
                            end

                            if (ipv4_packet && (ethernet_byte_index ==
                                    (l3_offset + ip_header_bytes + 8'd2)))
                                destination_port_high <= rx_completed_byte;

                            if (ipv4_packet && (ethernet_byte_index ==
                                    (l3_offset + ip_header_bytes + 8'd3)) &&
                                (destination_port_high == 8'd0) &&
                                (rx_completed_byte == 8'd23) &&
                                (protocol_tcp || protocol_udp))
                                rx_features[7] <= 1'b1;
                        end
                    end
                endcase
            end

            if (rx_active && !rx_dv) begin
                rx_active <= 1'b0;
                if (rx_drop) begin
                    no_buffer_frames <= no_buffer_frames + 32'd1;
                end else if (rx_bad || rx_overflow ||
                             (rx_length < MIN_FRAME_BYTES) ||
                             (rx_length > MAX_FRAME_LIMIT) ||
                             (rx_crc != ETH_CRC_RESIDUE)) begin
                    bad_frames <= bad_frames + 32'd1;
                    if (rx_bank == 1'b0)
                        bank_state_0 <= BANK_FREE;
                    else
                        bank_state_1 <= BANK_FREE;
                end else if (classifier_unwanted) begin
                    blocked_frames <= blocked_frames + 32'd1;
                    blocked_pulse <= 1'b1;
                    if (rx_bank == 1'b0)
                        bank_state_0 <= BANK_FREE;
                    else
                        bank_state_1 <= BANK_FREE;
                end else begin
                    accepted_frames <= accepted_frames + 32'd1;
                    if (rx_bank == 1'b0) begin
                        frame_length_0 <= rx_length;
                        frame_sequence_0 <= enqueue_sequence;
                        bank_state_0 <= BANK_READY;
                    end else begin
                        frame_length_1 <= rx_length;
                        frame_sequence_1 <= enqueue_sequence;
                        bank_state_1 <= BANK_READY;
                    end
                    enqueue_sequence <= enqueue_sequence + 16'd1;
                end
            end

            if (tx_ifg_count != 6'd0)
                tx_ifg_count <= tx_ifg_count - 6'd1;

            case (tx_state)
                TX_IDLE: begin
                    tx_en <= 1'b0;
                    tx_data <= 2'b00;
                    if ((tx_ifg_count == 6'd0) && output_link_100fd &&
                        ((bank_state_0 == BANK_READY) || (bank_state_1 == BANK_READY))) begin
                        tx_bank <= tx_select_bank_0 ? 1'b0 : 1'b1;
                        tx_length <= tx_select_bank_0 ? frame_length_0 : frame_length_1;
                        tx_index <= 12'd0;
                        tx_pair_count <= 2'd0;
                        if (tx_select_bank_0)
                            bank_state_0 <= BANK_SENDING;
                        else
                            bank_state_1 <= BANK_SENDING;
                        tx_state <= TX_PREFETCH;
                    end
                end
                TX_PREFETCH: begin
                    // The synchronous RAM read completes on this edge.
                    tx_pair_count <= 2'd0;
                    tx_state <= TX_SEND;
                end
                TX_SEND: begin
                    case (tx_pair_count)
                        2'd0: begin tx_en <= 1'b1; tx_data <= tx_byte[1:0]; tx_pair_count <= 2'd1; end
                        2'd1: begin tx_data <= tx_byte[3:2]; tx_pair_count <= 2'd2; end
                        2'd2: begin tx_data <= tx_byte[5:4]; tx_pair_count <= 2'd3; end
                        default: begin
                            tx_data <= tx_byte[7:6];
                            tx_pair_count <= 2'd0;
                            if ((tx_index + 12'd1) < tx_length) begin
                                tx_index <= tx_index + 12'd1;
                            end else begin
                                tx_state <= TX_DRAIN;
                            end
                        end
                    endcase
                end
                TX_DRAIN: begin
                    // Let the PHY sample the last upper dibit before ending TX_EN.
                    tx_en <= 1'b0;
                    tx_data <= 2'b00;
                    tx_ifg_count <= 6'd48;
                    tx_state <= TX_IDLE;
                    if (tx_bank == 1'b0)
                        bank_state_0 <= BANK_FREE;
                    else
                        bank_state_1 <= BANK_FREE;
                end
                default: begin
                    tx_state <= TX_IDLE;
                    tx_en <= 1'b0;
                    tx_data <= 2'b00;
                end
            endcase
        end
    end
endmodule
