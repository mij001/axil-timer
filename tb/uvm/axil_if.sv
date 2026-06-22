`timescale 1ns / 1ps

// the five channels as one interface. clocking blocks so a class does not race

interface axil_if #(
    parameter int ADDR_W = 12
) (
    input logic aclk,
    input logic aresetn
);

    logic              awvalid = 1'b0;
    logic              awready;
    logic [ADDR_W-1:0] awaddr;
    logic [2:0]        awprot;

    logic              wvalid  = 1'b0;
    logic              wready;
    logic [31:0]       wdata;
    logic [3:0]        wstrb;

    logic              bvalid;
    logic              bready  = 1'b0;
    logic [1:0]        bresp;

    logic              arvalid = 1'b0;
    logic              arready;
    logic [ADDR_W-1:0] araddr;
    logic [2:0]        arprot;

    logic              rvalid;
    logic              rready  = 1'b0;
    logic [31:0]       rdata;
    logic [1:0]        rresp;

    logic              irq;

    clocking drv_cb @(posedge aclk);
        default input #1step output #0;
        output awvalid, awaddr, awprot, wvalid, wdata, wstrb, bready,
               arvalid, araddr, arprot, rready;
        input  awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp, irq;
    endclocking

    clocking mon_cb @(posedge aclk);
        default input #1step;
        input awvalid, awready, awaddr, wvalid, wready, wdata, wstrb,
              bvalid, bready, bresp, arvalid, arready, araddr,
              rvalid, rready, rdata, rresp, irq;
    endclocking

    modport drv (clocking drv_cb, input aclk, aresetn);
    modport mon (clocking mon_cb, input aclk, aresetn);

endinterface
