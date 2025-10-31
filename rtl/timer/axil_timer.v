`timescale 1ns / 1ps

// top. structure only, no logic

module axil_timer #(
    parameter integer ADDR_W = 12
) (
    input  wire              aclk,
    input  wire              aresetn,

    input  wire              s_axil_awvalid,
    output wire              s_axil_awready,
    input  wire [ADDR_W-1:0] s_axil_awaddr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [2:0]        s_axil_awprot,   // not used, spec section 6
    /* verilator lint_on UNUSEDSIGNAL */

    input  wire              s_axil_wvalid,
    output wire              s_axil_wready,
    input  wire [31:0]       s_axil_wdata,
    input  wire [3:0]        s_axil_wstrb,

    output wire              s_axil_bvalid,
    input  wire              s_axil_bready,
    output wire [1:0]        s_axil_bresp,

    input  wire              s_axil_arvalid,
    output wire              s_axil_arready,
    input  wire [ADDR_W-1:0] s_axil_araddr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [2:0]        s_axil_arprot,   // not used, spec section 6
    /* verilator lint_on UNUSEDSIGNAL */

    output wire              s_axil_rvalid,
    input  wire              s_axil_rready,
    output wire [31:0]       s_axil_rdata,
    output wire [1:0]        s_axil_rresp,

    output wire              irq
);

    wire              reg_wr;
    wire [ADDR_W-1:0] reg_waddr;
    wire [31:0]       reg_wdata;
    wire [3:0]        reg_wstrb;
    wire              reg_werr;
    /* verilator lint_off UNUSEDSIGNAL */
    wire              reg_rd;       // the timer has no read side effects
    /* verilator lint_on UNUSEDSIGNAL */
    wire [ADDR_W-1:0] reg_raddr;
    wire [31:0]       reg_rdata;
    wire              reg_rerr;

    wire              ctrl_en;
    wire              ctrl_periodic;
    wire [15:0]       prescale;
    wire [31:0]       load_reload;
    wire              load_restart;
    wire [31:0]       load_value;
    wire [31:0]       core_count;
    wire              core_expire;

    axil_reg_bus #(.ADDR_W(ADDR_W)) u_bus (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .reg_wr         (reg_wr),
        .reg_waddr      (reg_waddr),
        .reg_wdata      (reg_wdata),
        .reg_wstrb      (reg_wstrb),
        .reg_werr       (reg_werr),
        .reg_rd         (reg_rd),
        .reg_raddr      (reg_raddr),
        .reg_rdata      (reg_rdata),
        .reg_rerr       (reg_rerr)
    );

    axil_timer_regs #(.ADDR_W(ADDR_W)) u_regs (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .reg_wr        (reg_wr),
        .reg_waddr     (reg_waddr),
        .reg_wdata     (reg_wdata),
        .reg_wstrb     (reg_wstrb),
        .reg_werr      (reg_werr),
        .reg_raddr     (reg_raddr),
        .reg_rdata     (reg_rdata),
        .reg_rerr      (reg_rerr),
        .core_count    (core_count),
        .core_expire   (core_expire),
        .ctrl_en       (ctrl_en),
        .ctrl_periodic (ctrl_periodic),
        .prescale      (prescale),
        .load_reload   (load_reload),
        .load_restart  (load_restart),
        .load_value    (load_value),
        .irq           (irq)
    );

    axil_timer_core u_core (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .en           (ctrl_en),
        .periodic     (ctrl_periodic),
        .prescale     (prescale),
        .load_reload  (load_reload),
        .load_restart (load_restart),
        .load_value   (load_value),
        .count        (core_count),
        .expire       (core_expire)
    );

endmodule
