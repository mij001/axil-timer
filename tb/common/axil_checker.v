`timescale 1ns / 1ps

// passive checker for one link. drives nothing

module axil_checker #(
    parameter integer ADDR_W = 12,
    parameter         NAME   = "axil"
) (
    input wire              aclk,
    input wire              aresetn,

    input wire              awvalid,
    input wire              awready,
    input wire [ADDR_W-1:0] awaddr,
    input wire [2:0]        awprot,

    input wire              wvalid,
    input wire              wready,
    input wire [31:0]       wdata,
    input wire [3:0]        wstrb,

    input wire              bvalid,
    input wire              bready,
    input wire [1:0]        bresp,

    input wire              arvalid,
    input wire              arready,
    input wire [ADDR_W-1:0] araddr,
    input wire [2:0]        arprot,

    input wire              rvalid,
    input wire              rready,
    input wire [31:0]       rdata,
    input wire [1:0]        rresp
);

    integer errors;
    integer n_aw, n_w, n_b, n_ar, n_r;      // completed handshakes so far

    // values at the previous rising edge
    reg              rst_p;
    reg              awvalid_p, awready_p;  reg [ADDR_W-1:0] awaddr_p; reg [2:0] awprot_p;
    reg              wvalid_p,  wready_p;   reg [31:0] wdata_p;        reg [3:0] wstrb_p;
    reg              bvalid_p,  bready_p;   reg [1:0]  bresp_p;
    reg              arvalid_p, arready_p;  reg [ADDR_W-1:0] araddr_p; reg [2:0] arprot_p;
    reg              rvalid_p,  rready_p;   reg [31:0] rdata_p;        reg [1:0] rresp_p;

    initial begin
        errors = 0;
        n_aw = 0; n_w = 0; n_b = 0; n_ar = 0; n_r = 0;
        rst_p = 1'b1;
        awvalid_p = 1'b0; awready_p = 1'b0; wvalid_p = 1'b0; wready_p = 1'b0;
        bvalid_p  = 1'b0; bready_p  = 1'b0; arvalid_p = 1'b0; arready_p = 1'b0;
        rvalid_p  = 1'b0; rready_p  = 1'b0;
    end

    task fail;
        input [8*72-1:0] msg;
        begin
            $display("[%0t] %s CHECK FAIL: %0s", $time, NAME, msg);
            errors = errors + 1;
        end
    endtask

    function is01;   // true when a one-bit signal is a clean 0 or 1
        input v;
        begin
            is01 = (v === 1'b0) || (v === 1'b1);
        end
    endfunction

    always @(posedge aclk) begin
        if (!aresetn) begin
            //  A3.1.2: during reset masters drive ARVALID, AWVALID, WVALID low, and
            if (awvalid !== 1'b0) fail("AWVALID not low during reset");
            if (wvalid  !== 1'b0) fail("WVALID not low during reset");
            if (arvalid !== 1'b0) fail("ARVALID not low during reset");
            if (bvalid  !== 1'b0) fail("BVALID not low during reset");
            if (rvalid  !== 1'b0) fail("RVALID not low during reset");
        end else begin
            // handshake wires must be clean after reset
            if (!is01(awvalid) || !is01(awready)) fail("AW handshake signal is X");
            if (!is01(wvalid)  || !is01(wready))  fail("W handshake signal is X");
            if (!is01(bvalid)  || !is01(bready))  fail("B handshake signal is X");
            if (!is01(arvalid) || !is01(arready)) fail("AR handshake signal is X");
            if (!is01(rvalid)  || !is01(rready))  fail("R handshake signal is X");

            //  A3.1.2 and Figure A3-1: earliest master VALID is at an edge after the
            if (rst_p && (awvalid === 1'b1 || wvalid === 1'b1 || arvalid === 1'b1))
                fail("master VALID high on the first edge after reset");

            //  A3.2.2: once asserted, VALID stays asserted until the edge after READY.
            if (!rst_p) begin
                if (awvalid_p && !awready_p) begin
                    if (awvalid !== 1'b1) fail("AWVALID dropped before handshake");
                    else if (awaddr !== awaddr_p || awprot !== awprot_p)
                        fail("AW payload changed while waiting");
                end
                if (wvalid_p && !wready_p) begin
                    if (wvalid !== 1'b1) fail("WVALID dropped before handshake");
                    else if (wdata !== wdata_p || wstrb !== wstrb_p)
                        fail("W payload changed while waiting");
                end
                if (bvalid_p && !bready_p) begin
                    if (bvalid !== 1'b1) fail("BVALID dropped before handshake");
                    else if (bresp !== bresp_p)
                        fail("BRESP changed while waiting");
                end
                if (arvalid_p && !arready_p) begin
                    if (arvalid !== 1'b1) fail("ARVALID dropped before handshake");
                    else if (araddr !== araddr_p || arprot !== arprot_p)
                        fail("AR payload changed while waiting");
                end
                if (rvalid_p && !rready_p) begin
                    if (rvalid !== 1'b1) fail("RVALID dropped before handshake");
                    else if (rdata !== rdata_p || rresp !== rresp_p)
                        fail("R payload changed while waiting");
                end
            end

            //  A3.3.1, AXI4 write response dependency: BVALID only after both the AW
            if (bvalid === 1'b1 && (n_aw <= n_b || n_w <= n_b))
                fail("BVALID before both AW and W handshakes");

            // A3.3.1, read dependency: RVALID only after the AR handshake
            if (rvalid === 1'b1 && n_ar <= n_r)
                fail("RVALID before the AR handshake");

            // B1.1.1: EXOKAY is not supported on AXI4-Lite
            if (bvalid === 1'b1 && bresp === 2'b01) fail("BRESP is EXOKAY");
            if (rvalid === 1'b1 && rresp === 2'b01) fail("RRESP is EXOKAY");

            // payload must be known while offered
            if (awvalid === 1'b1 && (^awaddr) === 1'bx) fail("AWADDR has X while valid");
            if (wvalid  === 1'b1 && ((^wdata) === 1'bx || (^wstrb) === 1'bx)) fail("W payload has X while valid");
            if (arvalid === 1'b1 && (^araddr) === 1'bx) fail("ARADDR has X while valid");
            if (rvalid  === 1'b1 && ((^rdata) === 1'bx || (^rresp) === 1'bx)) fail("R payload has X while valid");
            if (bvalid  === 1'b1 && (^bresp) === 1'bx) fail("BRESP has X while valid");

            // count handshakes completing at this edge
            if (awvalid === 1'b1 && awready === 1'b1) n_aw = n_aw + 1;
            if (wvalid  === 1'b1 && wready  === 1'b1) n_w  = n_w  + 1;
            if (bvalid  === 1'b1 && bready  === 1'b1) n_b  = n_b  + 1;
            if (arvalid === 1'b1 && arready === 1'b1) n_ar = n_ar + 1;
            if (rvalid  === 1'b1 && rready  === 1'b1) n_r  = n_r  + 1;
        end

        rst_p     <= !aresetn;
        awvalid_p <= awvalid; awready_p <= awready; awaddr_p <= awaddr; awprot_p <= awprot;
        wvalid_p  <= wvalid;  wready_p  <= wready;  wdata_p  <= wdata;  wstrb_p  <= wstrb;
        bvalid_p  <= bvalid;  bready_p  <= bready;  bresp_p  <= bresp;
        arvalid_p <= arvalid; arready_p <= arready; araddr_p <= araddr; arprot_p <= arprot;
        rvalid_p  <= rvalid;  rready_p  <= rready;  rdata_p  <= rdata;  rresp_p  <= rresp;
    end

    task report;
        begin
            $display("CHECKER %s: AW %0d, W %0d, B %0d, AR %0d, R %0d handshakes, %0d rule violations",
                     NAME, n_aw, n_w, n_b, n_ar, n_r, errors);
        end
    endtask

endmodule
