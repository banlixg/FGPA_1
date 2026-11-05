`timescale 1ns/1ps
module tb_sd_spi;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,req=0,cancel=0,ready=0;reg [31:0] lba=0;
    wire req_ready,valid,last,error,initialized,init_failed,hc,cs,sck,mosi;
    wire [3:0] code;wire [7:0] data;reg miso=1;
    team_sd_spi_reader #(.POWER_CYCLES(4),.SLOW_DIV(3),.FAST_DIV(2),
        .INIT_TRIES(8),.RESPONSE_BYTES(8),.TOKEN_BYTES(16)) dut(
        .clk(clk),.rst_n(rst_n),.initialized(initialized),.init_failed(init_failed),
        .error_code(code),.high_capacity(hc),.rd_req_valid(req),.rd_req_ready(req_ready),
        .rd_req_lba(lba),.rd_cancel(cancel),.rd_valid(valid),.rd_ready(ready),
        .rd_data(data),.rd_last(last),.rd_error(error),.sd_ncs(cs),.sd_dclk(sck),.sd_mosi(mosi),.sd_miso(miso));
    string mode;reg sdhc=1;reg [7:0] packet[0:5],queue[0:1023];
    integer bitn=0,pn=0,qread=0,qwrite=0,acmds=0,reads=0,checks=0;
    reg [7:0] incoming=0,outgoing=8'hff,tmp;
    reg [31:0] arg,sector_number;reg [15:0] crc;
    reg read_error=0;integer received=0;
    function [15:0] crc16(input [15:0] old,input [7:0] value);
        reg [15:0] c;begin c=old^{value,8'd0};for(integer i=0;i<8;i++)c=c[15]?((c<<1)^16'h1021):(c<<1);return c;end
    endfunction
    function [7:0] pattern(input integer sector,input integer pos);
        pattern=(sector*17+pos*29+(pos>>3))&255;
    endfunction
    task push(input [7:0] value);begin queue[qwrite]=value;qwrite=qwrite+1;end endtask
    task command;
        begin
            arg={packet[1],packet[2],packet[3],packet[4]};
            case(packet[0]&8'h3f)
                0:begin if(packet[5]!=8'h95)$fatal(1,"CMD0 CRC");push(1);end
                8:begin
                    if(arg!=32'h1aa || packet[5]!=8'h87)$fatal(1,"CMD8 packet");
                    if(mode!="no_response") begin push(1);push(0);push(0);push(1);push(mode=="bad_r7"?8'hab:8'haa);end
                end
                55:push(acmds<2?1:0);
                41:begin if(arg!=32'h40000000)$fatal(1,"HCS missing");acmds=acmds+1;push(acmds<2?1:0);end
                58:begin push(0);push(sdhc?8'hc0:8'h80);push(8'hff);push(8'h80);push(0);end
                16:begin if(sdhc || arg!=512)$fatal(1,"CMD16/address mode");push(0);end
                17:begin
                    sector_number=sdhc?arg:(arg>>9);reads=reads+1;
                    if(!sdhc && arg[8:0]!=0)$fatal(1,"SDSC unaligned");
                    if(sector_number!=lba)$fatal(1,"address mismatch");
                    push(mode=="r1_error"&&reads==1?4:0);
                    if(!(mode=="r1_error"&&reads==1)) begin
                        push(8'hff);
                        if(mode=="token_timeout"&&reads==1)begin end
                        else if(mode=="token_error"&&reads==1)push(8'h0b);
                        else begin
                            push(8'hfe);crc=0;
                            for(integer i=0;i<512;i++)begin tmp=pattern(sector_number,i);push(tmp);crc=crc16(crc,tmp);end
                            push(crc[15:8]);push(crc[7:0]^((mode=="crc_error"&&reads==1)?8'h01:8'h00));
                        end
                    end
                end
                default:$fatal(1,"unexpected command %0d",packet[0]);
            endcase
        end
    endtask
    always @(posedge cs) begin bitn=0;pn=0;qread=0;qwrite=0;incoming=0;outgoing=8'hff;miso=1;end
    always @(posedge sck) if(!cs) begin
        incoming={incoming[6:0],mosi};bitn=bitn+1;
        if(bitn==8)begin
            bitn=0;
            if(pn>0 || incoming[7:6]==2'b01)begin
                packet[pn]=incoming;
                if(pn==5)begin command();pn=0;end else pn=pn+1;
            end
        end
    end
    always @(negedge sck) if(!cs)begin
        if(bitn==0)begin
            outgoing=8'hff;
            if(qread<qwrite)begin outgoing=queue[qread];qread=qread+1;end
        end else outgoing={outgoing[6:0],1'b1};
        miso=outgoing[7];
    end
    reg [31:0] rng=32'h184fb9a1;reg held=0;reg [7:0] held_data;reg held_last;
    always @(posedge clk)if(rst_n)begin
        if(held&&!cancel)if(!valid||data!==held_data||last!==held_last)$fatal(1,"backpressure lost byte");
        held=valid&&!ready&&!cancel;held_data=data;held_last=last;
        if(error)read_error=1;
        if(valid&&ready)begin
            if(data!==pattern(lba,received)||last!==(received==511))$fatal(1,"byte mismatch %0d",received);
            received=received+1;checks=checks+1;
        end
    end
    always @(negedge clk)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};ready=(rng[3:0]==0);
    end
    task request(input [31:0] address);
        begin wait(req_ready);@(negedge clk);lba=address;received=0;read_error=0;req=1;@(negedge clk);req=0;end
    endtask
    initial begin
        if(!$value$plusargs("MODE=%s",mode))mode="sdhc";
        sdhc=(mode!="sdsc");repeat(4)@(negedge clk);rst_n=1;
        if(mode=="bad_r7"||mode=="no_response")begin
            wait(init_failed);repeat(500)@(negedge clk);
            if(initialized||req_ready)$fatal(1,"invalid card accepted");
            $display("TEST_PASS mode=%s init_rejected=1",mode);$finish;
        end
        wait(req_ready);if(hc!==sdhc)$fatal(1,"CCS decode");
        request(9032);
        if(mode=="cancel_physical")begin
            wait(dut.state==9&&dut.data_index==100);@(negedge clk);cancel=1;
            @(negedge clk);cancel=0;
            wait(req_ready);if(received||read_error)$fatal(1,"cancelled transaction leaked");
        end else if(mode=="cancel_stream")begin
            wait(received==17);@(negedge clk);cancel=1;@(negedge clk);cancel=0;
            wait(req_ready);held=0;
        end else if(mode=="crc_error"||mode=="r1_error"||mode=="token_error"||mode=="token_timeout")begin
            wait(read_error);wait(req_ready);
            if(received)$fatal(1,"failed sector leaked bytes");
        end else begin wait(received==512);wait(req_ready);end
        repeat(4)@(negedge clk);request(12345);wait(received==512);wait(req_ready);
        if(read_error)$fatal(1,"recovery failed");
        $display("TEST_PASS mode=%s bytes=%0d reads=%0d CCS=%0d",mode,checks,reads,hc);$finish;
    end
    initial begin #100000000;$fatal(1,"SPI watchdog state=%0d pn=%0d polls=%0d",dut.state,pn,dut.polls);end
endmodule
