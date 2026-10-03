`timescale 1ns / 1ps

module tb_breath_led;

    reg        sys_clk;
    reg        sys_rst_n;
    wire [3:0] led;

    // 连接官方呼吸灯模块
    breath_led uut (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .led       (led)
    );

    // 每隔 10ns 翻转一次，完整周期为 20ns，即 50MHz
    initial begin
        sys_clk = 1'b0;
    end

    always #10 sys_clk = ~sys_clk;

    // 开始时复位，100ns 后释放复位
    initial begin
        sys_rst_n = 1'b0;
        #100;
        sys_rst_n = 1'b1;
    end

endmodule