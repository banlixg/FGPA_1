`timescale 1ns/1ps
module tb_boot;
    parameter WIDTH=31,HEIGHT=17,MAX_LBA=4000,EXPECTED=4,REJECTED=0;
    localparam N=WIDTH*HEIGHT;
    reg clk=0;always #5 clk=~clk;reg rst_n=0,start=0;
    wire [3:0] mask,stage,code;wire [2:0] count;wire done,failed;
    wire [15:0] rejected;wire req,cancel,rr;wire [31:0] lba;
    reg active=0;integer sector=0,pos=0;wire rvalid=active;
    wire wvalid;wire [20:0] addr;wire [31:0] data;reg rsp=0;
    reg [7:0] card[0:(MAX_LBA+1)*512-1];reg present[0:MAX_LBA];
    reg [55:0] pixels[0:4*N-1];reg [31:0] expected_mem[0:4*N-1],memory[0:4*N-1];
    string base;integer checks=0,requests=0;reg [55:0] p;
    team_boot_loader #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT),.WAIT_LIMIT(1000)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.slot_valid(mask),.image_count(count),
        .finished(done),.failed(failed),.stage(stage),.error_code(code),.rejected_count(rejected),
        .rd_req_valid(req),.rd_req_ready(!active),.rd_req_lba(lba),.rd_cancel(cancel),
        .rd_valid(rvalid),.rd_ready(rr),.rd_data(card[sector*512+pos]),.rd_last(pos==511),.rd_error(1'b0),
        .wr_valid(wvalid),.wr_ready(!rsp),.wr_addr(addr),.wr_data(data),.wr_rsp_valid(rsp),.wr_rsp_error(1'b0));
    always @(posedge clk)if(rst_n)begin
        rsp<=0;
        if(wvalid&&!rsp)begin
            if(addr>=4*N||mask[addr/N])$fatal(1,"invalid overwrite");
            if(data!==expected_mem[addr])$fatal(1,"memory mismatch addr=%0d",addr);
            memory[addr]<=data;rsp<=1;checks=checks+1;
        end
        if(cancel)active<=0;
        else if(active&&rr)begin if(pos==511)active<=0;else pos<=pos+1;end
        else if(!active&&req)begin
            if(lba>MAX_LBA||present[lba]!==1)$fatal(1,"bad sector %0d",lba);
            sector<=lba;pos<=0;active<=1;requests=requests+1;
        end
    end
    initial begin
        if(!$value$plusargs("BASE=%s",base))$fatal(1,"BASE missing");
        $readmemh({base,"/card.hex"},card);$readmemh({base,"/present.hex"},present);
        $readmemh({base,"/pixels.hex"},pixels);
        for(integer f=0;f<4;f++)for(integer i=0;i<N;i++)begin
            p=pixels[f*N+i];expected_mem[f*N+p[39:24]*WIDTH+p[55:40]]={p[23:0],8'd0};
        end
        repeat(4)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
        wait(done||stage==6);repeat(4)@(negedge clk);
        if(!done||count!=EXPECTED||mask!=((1<<EXPECTED)-1)||rejected!=REJECTED||failed!=(EXPECTED<4))
            $fatal(1,"boot result count=%0d rejected=%0d stage=%0d error=%0d",count,rejected,stage,code);
        if(checks!=EXPECTED*N)$fatal(1,"write count");
        $display("TEST_PASS frames=%0d rejected=%0d writes=%0d sectors=%0d",count,rejected,checks,requests);$finish;
    end
    initial begin #2000000000;$fatal(1,"boot watchdog stage=%0d",stage);end
endmodule
