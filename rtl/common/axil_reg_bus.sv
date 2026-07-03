`timescale 1ns / 1ps

// axi4-lite slave front end. five channels in, a small register bus out
//   reg_wr reg_waddr reg_wdata reg_wstrb   one write, held here
//   reg_rd reg_raddr                       one read, do side effects now
//   reg_werr reg_rerr reg_rdata            answers back
// written for the timer, reused by the uart with reg_rd added

module axil_reg_bus #(
    parameter int ADDR_W = 12
) (
    input  logic              aclk,
    input  logic              aresetn,

    // AXI4-Lite slave: write address channel
    input  logic              s_axil_awvalid,
    output logic               s_axil_awready,
    input  logic [ADDR_W-1:0] s_axil_awaddr,

    // AXI4-Lite slave: write data channel
    input  logic              s_axil_wvalid,
    output logic               s_axil_wready,
    input  logic [31:0]       s_axil_wdata,
    input  logic [3:0]        s_axil_wstrb,

    // AXI4-Lite slave: write response channel
    output logic               s_axil_bvalid,
    input  logic              s_axil_bready,
    output logic  [1:0]        s_axil_bresp,

    // AXI4-Lite slave: read address channel
    input  logic              s_axil_arvalid,
    output logic               s_axil_arready,
    input  logic [ADDR_W-1:0] s_axil_araddr,

    // AXI4-Lite slave: read data channel
    output logic               s_axil_rvalid,
    input  logic              s_axil_rready,
    output logic  [31:0]       s_axil_rdata,
    output logic  [1:0]        s_axil_rresp,

    // register bus towards the register block
    output logic               reg_wr,
    output logic  [ADDR_W-1:0] reg_waddr,
    output logic  [31:0]       reg_wdata,
    output logic  [3:0]        reg_wstrb,
    input  logic              reg_werr,

    output logic              reg_rd,
    output logic [ADDR_W-1:0] reg_raddr,
    input  logic [31:0]       reg_rdata,
    input  logic              reg_rerr
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // every register is a pair of names: _q is its value now, _d next cycle
    logic aw_full_q, aw_full_d;   // an accepted write address is held
    logic [ADDR_W-1:0] awaddr_q,  awaddr_d;
    logic w_full_q,  w_full_d;    // an accepted write data beat is held
    logic [31:0]       wdata_q,   wdata_d;
    logic [3:0]        wstrb_q,   wstrb_d;
    logic bvalid_q,  bvalid_d;    // a write response is being offered
    logic [1:0]        bresp_q,   bresp_d;
    logic rvalid_q,  rvalid_d;    // a read response is being offered
    logic [31:0]       rdata_q,   rdata_d;
    logic [1:0]        rresp_q,   rresp_d;

    // named "now" helpers. plain gates
    logic aw_hs;
    assign aw_hs = s_axil_awvalid & s_axil_awready;   // AW handshake this cycle
    logic w_hs;
    assign w_hs = s_axil_wvalid  & s_axil_wready;    // w handshake this cycle
    logic b_hs;
    assign b_hs = s_axil_bvalid  & s_axil_bready;    // b handshake this cycle
    logic ar_hs;
    assign ar_hs = s_axil_arvalid & s_axil_arready;   // AR handshake this cycle
    logic r_hs;
    assign r_hs = s_axil_rvalid  & s_axil_rready;    // r handshake this cycle

    // both halves of a write are held, and the response channel is free
    logic wr_go;
    assign wr_go = aw_full_q & w_full_q & ~bvalid_q;

    // the register block looks the read address up in the same cycle
    assign reg_raddr = s_axil_araddr;
    assign reg_rd    = ar_hs;

    // b1
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_full_q <= 1'b0;
            awaddr_q  <= {ADDR_W{1'b0}};
            w_full_q  <= 1'b0;
            wdata_q   <= 32'd0;
            wstrb_q   <= 4'd0;
            bvalid_q  <= 1'b0;
            bresp_q   <= RESP_OKAY;
            rvalid_q  <= 1'b0;
            rdata_q   <= 32'd0;
            rresp_q   <= RESP_OKAY;
        end else begin
            aw_full_q <= aw_full_d;
            awaddr_q  <= awaddr_d;
            w_full_q  <= w_full_d;
            wdata_q   <= wdata_d;
            wstrb_q   <= wstrb_d;
            bvalid_q  <= bvalid_d;
            bresp_q   <= bresp_d;
            rvalid_q  <= rvalid_d;
            rdata_q   <= rdata_d;
            rresp_q   <= rresp_d;
        end
    end

    // b2
    always_comb begin
        // defaults: every stored value holds
        aw_full_d = aw_full_q;
        awaddr_d  = awaddr_q;
        w_full_d  = w_full_q;
        wdata_d   = wdata_q;
        wstrb_d   = wstrb_q;
        bvalid_d  = bvalid_q;
        bresp_d   = bresp_q;
        rvalid_d  = rvalid_q;
        rdata_d   = rdata_q;
        rresp_d   = rresp_q;

        // write address channel. capture on handshake
        if (aw_hs) begin
            aw_full_d = 1'b1;
            awaddr_d  = s_axil_awaddr;
        end

        // write data channel. capture on handshake
        if (w_hs) begin
            w_full_d = 1'b1;
            wdata_d  = s_axil_wdata;
            wstrb_d  = s_axil_wstrb;
        end

        // both halves held and no response pending: the write is applied this cycle
        if (wr_go) begin
            aw_full_d = 1'b0;
            w_full_d  = 1'b0;
            bvalid_d  = 1'b1;
            bresp_d   = reg_werr ? RESP_SLVERR : RESP_OKAY;
        end

        // write response channel. b_hs and wr_go cannot both be true
        if (b_hs) begin
            bvalid_d = 1'b0;
        end

        // read address channel. look up and capture the answer on handshake
        if (ar_hs) begin
            rvalid_d = 1'b1;
            rdata_d  = reg_rerr ? 32'd0 : reg_rdata;
            rresp_d  = reg_rerr ? RESP_SLVERR : RESP_OKAY;
        end

        // read data channel. ar_hs needs rvalid_q low and r_hs needs it high
        if (r_hs) begin
            rvalid_d = 1'b0;
        end
    end

    // b3
    always_comb begin
        s_axil_awready = ~aw_full_q;
        s_axil_wready  = ~w_full_q;
        s_axil_bvalid  = bvalid_q;
        s_axil_bresp   = bresp_q;
        s_axil_arready = ~rvalid_q;
        s_axil_rvalid  = rvalid_q;
        s_axil_rdata   = rdata_q;
        s_axil_rresp   = rresp_q;

        reg_wr    = aw_full_q & w_full_q & ~bvalid_q;
        reg_waddr = awaddr_q;
        reg_wdata = wdata_q;
        reg_wstrb = wstrb_q;
    end

endmodule
