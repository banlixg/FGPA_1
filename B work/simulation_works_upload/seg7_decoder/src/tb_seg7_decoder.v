`timescale 1ns / 1ps

module tb_seg7_decoder;

    reg  [3:0] A;
    wire [6:0] LED7S;
    wire [7:0] B;

    integer i;

    // 连接官方七段译码器
    DECL7S uut (
        .A     (A),
        .LED7S (LED7S),
        .B     (B)
    );

    initial begin
        // 依次测试十进制 0～15，即十六进制 0～F
        for (i = 0; i < 16; i = i + 1) begin
            A = i[3:0];
            #100;
        end

        // 全部测试完毕后暂停
        $stop;
    end

endmodule