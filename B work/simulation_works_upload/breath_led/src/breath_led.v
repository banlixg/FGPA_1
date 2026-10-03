//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           led_twinkle
// Last modified Date:  2019/4/14 10:55:56
// Last Version:        V1.0
// Descriptions:        按键控制LED
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/4/14 10:55:56
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module breath_led(
    input   sys_clk   ,  //时钟信号50Mhz
    input   sys_rst_n ,  //复位信号

    output [3:0] led          //LED
);

//reg define
reg  [15:0]  period_cnt ;   //周期计数器频率：1khz 周期:1ms  计数值:1ms/20ns=50000
reg  [15:0]  duty_cycle ;   //占空比数值
reg          inc_dec_flag ; //0 递增  1 递减

//*****************************************************
//**                  main code
//*****************************************************

//根据占空比和计数值之间的大小关系来输出LED
assign   led = (period_cnt >= duty_cycle) ?  1'b1  :  1'b0;

//周期计数器
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        period_cnt <= 16'd0;
    else if(period_cnt == 16'd50000)
        period_cnt <= 16'd0;
    else
        period_cnt <= period_cnt + 1'b1;
end

//在周期计数器的节拍下递增或递减占空比
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        duty_cycle   <= 16'd0;
        inc_dec_flag <= 1'b0;
    end
    else begin
        if(period_cnt == 16'd50000) begin    //计满1ms
            if(inc_dec_flag == 1'b0) begin   //占空比递增状态
                if(duty_cycle == 16'd50000)  //如果占空比已递增至最大
                    inc_dec_flag <= 1'b1;    //则占空比开始递减
                else                         //否则占空比以25为单位递增
                    duty_cycle <= duty_cycle + 16'd25;
            end
            else begin                       //占空比递减状态
                if(duty_cycle == 16'd0)      //如果占空比已递减至0
                    inc_dec_flag <= 1'b0;    //则占空比开始递增
                else                         //否则占空比以25为单位递减
                    duty_cycle <= duty_cycle - 16'd25;
            end
        end
    end
end

endmodule
