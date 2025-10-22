`timescale 1ns / 1ps

// the register map. every collision rule is a row in docs/axil_timer_decisions.md

module axil_timer_regs #(
    parameter integer ADDR_W = 12
) (
    input  wire              aclk,
    input  wire              aresetn,

    // register bus from the AXI4-Lite front end
    input  wire              reg_wr,
    input  wire [ADDR_W-1:0] reg_waddr,
    input  wire [31:0]       reg_wdata,
    input  wire [3:0]        reg_wstrb,
    output reg               reg_werr,
    input  wire [ADDR_W-1:0] reg_raddr,
    output reg  [31:0]       reg_rdata,
    output reg               reg_rerr,

    // from the counter core
    input  wire [31:0]       core_count,
    input  wire              core_expire,     // one cycle: the timer expires now

    // to the counter core
    output reg               ctrl_en,
    output reg               ctrl_periodic,
    output reg  [15:0]       prescale,
    output reg  [31:0]       load_reload,     // LOAD register, for periodic reload
    output reg               load_restart,    // same cycle: restart the count
    output reg  [31:0]       load_value,      // same cycle: the value to restart from

    output reg               irq
);

    localparam [ADDR_W-1:0] OFF_CTRL     = {{(ADDR_W-8){1'b0}}, 8'h00};
    localparam [ADDR_W-1:0] OFF_LOAD     = {{(ADDR_W-8){1'b0}}, 8'h04};
    localparam [ADDR_W-1:0] OFF_COUNT    = {{(ADDR_W-8){1'b0}}, 8'h08};
    localparam [ADDR_W-1:0] OFF_STATUS   = {{(ADDR_W-8){1'b0}}, 8'h0C};
    localparam [ADDR_W-1:0] OFF_PRESCALE = {{(ADDR_W-8){1'b0}}, 8'h10};

    // registers
    reg        en_q,       en_d;
    reg        periodic_q, periodic_d;
    reg        irq_en_q,   irq_en_d;
    reg [31:0] load_q,     load_d;
    reg [15:0] prescale_q, prescale_d;
    reg        expired_q,  expired_d;

    // named "now" helpers. plain gates
    wire [31:0] wmask = {{8{reg_wstrb[3]}}, {8{reg_wstrb[2]}},
                         {8{reg_wstrb[1]}}, {8{reg_wstrb[0]}}};

    wire wr_ctrl     = reg_wr & (reg_waddr == OFF_CTRL);
    wire wr_load     = reg_wr & (reg_waddr == OFF_LOAD);
    wire wr_status   = reg_wr & (reg_waddr == OFF_STATUS);
    wire wr_prescale = reg_wr & (reg_waddr == OFF_PRESCALE);

    // values the registers would take if this write were applied, byte by byte
    wire [31:0] load_merged     = (load_q & ~wmask) | (reg_wdata & wmask);
    wire [15:0] prescale_merged = (prescale_q & ~wmask[15:0]) | (reg_wdata[15:0] & wmask[15:0]);

    // software asks to clear EXPIRED this cycle
    wire w1c_expired = wr_status & reg_wstrb[0] & reg_wdata[0];

    //  ------------------------------------------------------------------------- Block
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            en_q       <= 1'b0;
            periodic_q <= 1'b0;
            irq_en_q   <= 1'b0;
            load_q     <= 32'd0;
            prescale_q <= 16'd0;
            expired_q  <= 1'b0;
        end else begin
            en_q       <= en_d;
            periodic_q <= periodic_d;
            irq_en_q   <= irq_en_d;
            load_q     <= load_d;
            prescale_q <= prescale_d;
            expired_q  <= expired_d;
        end
    end

    //  ------------------------------------------------------------------------- Block
    always @(*) begin
        // next values. defaults: hold
        en_d       = en_q;
        periodic_d = periodic_q;
        irq_en_d   = irq_en_q;
        load_d     = load_q;
        prescale_d = prescale_q;
        expired_d  = expired_q;

        //  CTRL. all three fields live in byte 0. a CTRL write wins over a one-shot
        if (wr_ctrl && reg_wstrb[0]) begin
            en_d       = reg_wdata[0];
            periodic_d = reg_wdata[1];
            irq_en_d   = reg_wdata[2];
        end else if (core_expire && !periodic_q) begin
            en_d       = 1'b0;
        end

        // LOAD
        if (wr_load)
            load_d = load_merged;

        // PRESCALE. only bytes 0 and 1 exist. bytes 2 and 3 are ignored
        if (wr_prescale)
            prescale_d = prescale_merged;

        // STATUS. set wins: an expiry in the same cycle as a clear is kept
        if (core_expire)
            expired_d = 1'b1;
        else if (w1c_expired)
            expired_d = 1'b0;

        //  same-cycle commands to the core. a LOAD write with no strobes set is not a
        load_restart = wr_load & (|reg_wstrb);
        load_value   = load_merged;

        // same-cycle answer to the bus: is the address being written valid?
        case (reg_waddr)
            OFF_CTRL, OFF_LOAD, OFF_STATUS, OFF_PRESCALE: reg_werr = 1'b0;
            default:                                     reg_werr = 1'b1;
        endcase

        // same-cycle answer to the bus: what is at the address being read?
        reg_rerr  = 1'b0;
        reg_rdata = 32'd0;
        case (reg_raddr)
            OFF_CTRL:     reg_rdata = {29'd0, irq_en_q, periodic_q, en_q};
            OFF_LOAD:     reg_rdata = load_q;
            OFF_COUNT:    reg_rdata = core_count;
            OFF_STATUS:   reg_rdata = {31'd0, expired_q};
            OFF_PRESCALE: reg_rdata = {16'd0, prescale_q};
            default:      reg_rerr  = 1'b1;
        endcase
    end

    //  ------------------------------------------------------------------------- Block
    always @(*) begin
        ctrl_en       = en_q;
        ctrl_periodic = periodic_q;
        prescale      = prescale_q;
        load_reload   = load_q;
        irq           = expired_q & irq_en_q;
    end

endmodule
