`timescale 1ns / 1ps

// prescaler and down counter, spec section 4. no clock divider, tick is an enable

module axil_timer_core (
    input  logic        aclk,
    input  logic        aresetn,

    // from the register block
    input  logic        en,
    input  logic        periodic,
    input  logic [15:0] prescale,
    input  logic [31:0] load_reload,
    input  logic        load_restart,
    input  logic [31:0] load_value,

    // to the register block
    output logic  [31:0] count,
    output logic         expire       // one cycle: the timer expires now
);

    // registers
    logic [15:0] pre_q,   pre_d;
    logic [31:0] count_q, count_d;

    // named "now" helpers. plain gates
    logic tick;
    assign tick = en & (pre_q >= prescale);
    logic count_zero;
    assign count_zero = (count_q == 32'd0);

    // b1
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            pre_q   <= 16'd0;
            count_q <= 32'd0;
        end else begin
            pre_q   <= pre_d;
            count_q <= count_d;
        end
    end

    // b2
    always_comb begin
        pre_d   = pre_q;
        count_d = count_q;

        // the expiry is a fact about this cycle. it does not depend on whether
        expire = tick & count_zero;

        if (load_restart) begin
            // software's new start value wins for COUNT and the prescaler phase
            pre_d   = 16'd0;
            count_d = load_value;
        end else if (!en) begin
            pre_d   = 16'd0;
        end else if (tick) begin
            pre_d = 16'd0;
            if (!count_zero)
                count_d = count_q - 32'd1;
            else if (periodic)
                count_d = load_reload;
            // one-shot expiry: COUNT stays zero, the register block clears EN
        end else begin
            pre_d = pre_q + 16'd1;
        end
    end

    // b3
    always_comb begin
        count = count_q;
    end

endmodule
