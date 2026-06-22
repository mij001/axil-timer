// one agent, a shadow scoreboard and a coverage collector off the monitor

class axil_env extends uvm_env;

   `uvm_component_utils(axil_env)

   axil_agent      agt;
   axil_scoreboard sb;
   axil_coverage   cov;

   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agt = axil_agent::type_id::create("agt", this);
      sb  = axil_scoreboard::type_id::create("sb", this);
      cov = axil_coverage::type_id::create("cov", this);
   endfunction

   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agt.mon.ap.connect(sb.analysis_export);
      agt.mon.ap.connect(cov.analysis_export);
   endfunction

endclass : axil_env
