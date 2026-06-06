`timescale 1ns / 1ps

// top. structure only, no logic

module axil_timer #(
    parameter int ADDR_W = 12
) (
    input  logic              aclk,
    input  logic              aresetn,

    input  logic              s_axil_awvalid,
    output logic              s_axil_awready,
    input  logic [ADDR_W-1:0] s_axil_awaddr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [2:0]        s_axil_awprot,   // not used, spec section 6
    /* verilator lint_on UNUSEDSIGNAL */

    input  logic              s_axil_wvalid,
    output logic              s_axil_wready,
    input  logic [31:0]       s_axil_wdata,
    input  logic [3:0]        s_axil_wstrb,

    output logic              s_axil_bvalid,
    input  logic              s_axil_bready,
    output logic [1:0]        s_axil_bresp,

    input  logic              s_axil_arvalid,
    output logic              s_axil_arready,
    input  logic [ADDR_W-1:0] s_axil_araddr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [2:0]        s_axil_arprot,   // not used, spec section 6
    /* verilator lint_on UNUSEDSIGNAL */

    output logic              s_axil_rvalid,
    input  logic              s_axil_rready,
    output logic [31:0]       s_axil_rdata,
    output logic [1:0]        s_axil_rresp,

    output logic              irq
);

    logic reg_wr;
    logic [ADDR_W-1:0] reg_waddr;
    logic [31:0]       reg_wdata;
    logic [3:0]        reg_wstrb;
    logic reg_werr;
    /* verilator lint_off UNUSEDSIGNAL */
    logic reg_rd;       // the timer has no read side effects
    /* verilator lint_on UNUSEDSIGNAL */
    logic [ADDR_W-1:0] reg_raddr;
    logic [31:0]       reg_rdata;
    logic reg_rerr;

    logic ctrl_en;
    logic ctrl_periodic;
    logic [15:0]       prescale;
    logic [31:0]       load_reload;
    logic load_restart;
    logic [31:0]       load_value;
    logic [31:0]       core_count;
    logic core_expire;

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
