`timescale 1ns / 1ps

module tb_key_led;

    reg        sys_clk;
    reg        sys_rst_n;
    reg  [3:0] key;
    wire [3:0] led;

    // 连接被测试的官方模块
    key_led uut (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .key       (key),
        .led       (led)
    );

    // 50MHz 时钟：每 10ns 翻转一次
    initial sys_clk = 1'b0;
    always #10 sys_clk = ~sys_clk;

    initial begin
        // 初始复位，所有按键松开
        sys_rst_n = 1'b0;
        key = 4'b1111;
        #100;
        sys_rst_n = 1'b1;
        #100;

        // 测试按键1：按住 1000ns，然后松开
        key = 4'b1110;
        #1000;
        key = 4'b1111;
        #100;

        // 复位后，测试按键2
        sys_rst_n = 1'b0;
        #100;
        sys_rst_n = 1'b1;
        key = 4'b1101;
        #1000;
        key = 4'b1111;
        #100;

        // 复位后，测试按键3
        sys_rst_n = 1'b0;
        #100;
        sys_rst_n = 1'b1;
        key = 4'b1011;
        #1000;
        key = 4'b1111;
        #100;

        // 复位后，测试按键4
        sys_rst_n = 1'b0;
        #100;
        sys_rst_n = 1'b1;
        key = 4'b0111;
        #500;

        // 最后松开所有按键，再暂停仿真
        key = 4'b1111;
        #200;
        $stop;
    end

endmodule