// FIR 滤波器包装模块
// 功能：封装 Xilinx FIR Compiler IP，适配项目 valid/data 接口
// 内部处理 Offset Binary ↔ 二进制补码 转换
module fir_filter #(
    parameter FIR_OUT_WIDTH = 30   // FIR Compiler IP 实际输出位宽，需与IP配置匹配
) (
    input  wire        clk,        // 系统工作时钟
    input  wire [11:0] din,        // 输入数据（12bit，Offset Binary 格式）
    input  wire        din_valid,  // 输入数据有效标志

    output wire [11:0] dout,       // 输出数据（12bit，Offset Binary 格式）
    output wire        dout_valid  // 输出数据有效标志
);

    // =========================================================================
    // 输入格式转换：Offset Binary → 二进制补码
    // =========================================================================
    // Offset Binary: 0x000=-满幅, 0x800=零点, 0xFFF=+满幅
    // 补码:          0x800=-满幅, 0x000=零点, 0x7FF=+满幅
    // 转换方法：反转最高位
    wire signed [11:0] signed_din = {~din[11], din[10:0]};

    // 符号扩展到 16bit（FIR Compiler 输入位宽对齐字节边界）
    wire [15:0] fir_din = {{4{signed_din[11]}}, signed_din};

    // =========================================================================
    // 例化 Xilinx FIR Compiler IP
    // =========================================================================
    // 用户需在 Vivado IP Catalog 中配置：
    //   - Coefficient Source: COE File (matlab/fir_lpf_125k_275k_2m.coe)
    //   - Input Data Width: 12
    //   - Coefficient Width: 16
    //   - 实例名: fir_compiler_0
    wire [31:0] fir_dout_raw;   // IP 端口固定 32bit（字节对齐），有效数据为低 FIR_OUT_WIDTH 位
    wire        fir_dout_valid;

    wire [FIR_OUT_WIDTH-1:0] fir_dout = fir_dout_raw[FIR_OUT_WIDTH-1:0];

    fir_compiler_0 u_fir (
        .aclk               (clk),
        .s_axis_data_tdata  (fir_din),
        .s_axis_data_tvalid (din_valid),
        .s_axis_data_tready (),             // 不使用背压
        .m_axis_data_tdata  (fir_dout_raw),
        .m_axis_data_tvalid (fir_dout_valid)
    );

    // =========================================================================
    // 输出格式转换：截取高12位 + 补码 → Offset Binary
    // =========================================================================
    // 截取 FIR 输出的高 12 位（丢弃低位精度位）
    wire signed [11:0] signed_dout = fir_dout[FIR_OUT_WIDTH-1 -: 12];

    // 补码 → Offset Binary：反转最高位
    assign dout       = {~signed_dout[11], signed_dout[10:0]};
    assign dout_valid = fir_dout_valid;

endmodule
