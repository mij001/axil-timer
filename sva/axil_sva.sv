`timescale 1ns / 1ps

// axi4-lite rules as sva. binds onto axil_reg_bus so it checks the uart too

module axil_sva #(
    parameter int    ADDR_W = 12,
    parameter string NAME   = "axil"
) (
    input logic              aclk,
    input logic              aresetn,

    input logic              awvalid, awready,
    input logic [ADDR_W-1:0] awaddr,

    input logic              wvalid,  wready,
    input logic [31:0]       wdata,
    input logic [3:0]        wstrb,

    input logic              bvalid,  bready,
    input logic [1:0]        bresp,

    input logic              arvalid, arready,
    input logic [ADDR_W-1:0] araddr,

    input logic              rvalid,  rready,
    input logic [31:0]       rdata,
    input logic [1:0]        rresp
);

    // reset. every VALID is low while aresetn is low. a3.1.2
    a_rst_awvalid: assert property (@(posedge aclk) (!aresetn) |-> (awvalid === 1'b0))
        else $error("%s: AWVALID not low during reset", NAME);
    a_rst_wvalid:  assert property (@(posedge aclk) (!aresetn) |-> (wvalid  === 1'b0))
        else $error("%s: WVALID not low during reset", NAME);
    a_rst_bvalid:  assert property (@(posedge aclk) (!aresetn) |-> (bvalid  === 1'b0))
        else $error("%s: BVALID not low during reset", NAME);
    a_rst_arvalid: assert property (@(posedge aclk) (!aresetn) |-> (arvalid === 1'b0))
        else $error("%s: ARVALID not low during reset", NAME);
    a_rst_rvalid:  assert property (@(posedge aclk) (!aresetn) |-> (rvalid  === 1'b0))
        else $error("%s: RVALID not low during reset", NAME);

    // once VALID is asserted it stays asserted until the handshake. a3.2.1
    a_aw_holds: assert property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && !awready) |=> awvalid)
        else $error("%s: AWVALID dropped before the handshake", NAME);
    a_w_holds:  assert property (@(posedge aclk) disable iff (!aresetn)
        (wvalid  && !wready)  |=> wvalid)
        else $error("%s: WVALID dropped before the handshake", NAME);
    a_b_holds:  assert property (@(posedge aclk) disable iff (!aresetn)
        (bvalid  && !bready)  |=> bvalid)
        else $error("%s: BVALID dropped before the handshake", NAME);
    a_ar_holds: assert property (@(posedge aclk) disable iff (!aresetn)
        (arvalid && !arready) |=> arvalid)
        else $error("%s: ARVALID dropped before the handshake", NAME);
    a_r_holds:  assert property (@(posedge aclk) disable iff (!aresetn)
        (rvalid  && !rready)  |=> rvalid)
        else $error("%s: RVALID dropped before the handshake", NAME);

    // the payload does not move while the channel is waiting
    a_aw_stable: assert property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && !awready) |=> $stable(awaddr))
        else $error("%s: AWADDR changed while waiting", NAME);
    a_w_stable:  assert property (@(posedge aclk) disable iff (!aresetn)
        (wvalid && !wready) |=> ($stable(wdata) && $stable(wstrb)))
        else $error("%s: WDATA or WSTRB changed while waiting", NAME);
    a_b_stable:  assert property (@(posedge aclk) disable iff (!aresetn)
        (bvalid && !bready) |=> $stable(bresp))
        else $error("%s: BRESP changed while waiting", NAME);
    a_ar_stable: assert property (@(posedge aclk) disable iff (!aresetn)
        (arvalid && !arready) |=> $stable(araddr))
        else $error("%s: ARADDR changed while waiting", NAME);
    a_r_stable:  assert property (@(posedge aclk) disable iff (!aresetn)
        (rvalid && !rready) |=> ($stable(rdata) && $stable(rresp)))
        else $error("%s: R payload changed while waiting", NAME);

    // nothing offered may be unknown
    a_known_ctrl: assert property (@(posedge aclk) disable iff (!aresetn)
        !$isunknown({awvalid, awready, wvalid, wready, bvalid, bready,
                     arvalid, arready, rvalid, rready}))
        else $error("%s: X or Z on a handshake wire", NAME);

    a_known_b: assert property (@(posedge aclk) disable iff (!aresetn)
        bvalid |-> !$isunknown(bresp))
        else $error("%s: X in BRESP while BVALID is high", NAME);

    a_known_r: assert property (@(posedge aclk) disable iff (!aresetn)
        rvalid |-> !$isunknown({rdata, rresp}))
        else $error("%s: X in the read payload while RVALID is high", NAME);

    // a slave must not wait for the other half of a write before taking the half it
    a_aw_independent: assert property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && !wvalid) |-> ##[0:3] awready)
        else $error("%s: AWREADY appears to be waiting for WVALID", NAME);

    a_w_independent: assert property (@(posedge aclk) disable iff (!aresetn)
        (wvalid && !awvalid) |-> ##[0:3] wready)
        else $error("%s: WREADY appears to be waiting for AWVALID", NAME);

    c_aw_before_w: cover property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && awready && !(wvalid && wready)) ##[1:8] (wvalid && wready));

    c_w_before_aw: cover property (@(posedge aclk) disable iff (!aresetn)
        (wvalid && wready && !(awvalid && awready)) ##[1:8] (awvalid && awready));

    c_aw_w_together: cover property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && awready && wvalid && wready));

    c_b_stalled: cover property (@(posedge aclk) disable iff (!aresetn)
        (bvalid && !bready)[*2] ##1 (bvalid && bready));

    c_r_stalled: cover property (@(posedge aclk) disable iff (!aresetn)
        (rvalid && !rready)[*2] ##1 (rvalid && rready));

    c_slverr_write: cover property (@(posedge aclk) disable iff (!aresetn)
        (bvalid && bready && bresp == 2'b10));

    c_slverr_read: cover property (@(posedge aclk) disable iff (!aresetn)
        (rvalid && rready && rresp == 2'b10));

    c_back_to_back_writes: cover property (@(posedge aclk) disable iff (!aresetn)
        (bvalid && bready) ##1 (bvalid && bready));

endmodule


// one bind, both designs. axil_reg_bus is the front end of the timer and of the UART,
bind axil_reg_bus axil_sva #(
    .ADDR_W (ADDR_W),
    .NAME   ("axil")
) u_sva (
    .aclk    (aclk),    .aresetn (aresetn),
    .awvalid (s_axil_awvalid), .awready (s_axil_awready), .awaddr (s_axil_awaddr),
    .wvalid  (s_axil_wvalid),  .wready  (s_axil_wready),  .wdata  (s_axil_wdata),
    .wstrb   (s_axil_wstrb),
    .bvalid  (s_axil_bvalid),  .bready  (s_axil_bready),  .bresp  (s_axil_bresp),
    .arvalid (s_axil_arvalid), .arready (s_axil_arready), .araddr (s_axil_araddr),
    .rvalid  (s_axil_rvalid),  .rready  (s_axil_rready),  .rdata  (s_axil_rdata),
    .rresp   (s_axil_rresp)
);
