// FFT 核心模块
// 功能：收集 1024 个 ADC 样本 → 驱动 Xilinx FFT IP → 计算幅值 → 存入 RAM
// 上电后仅执行一次 FFT，完成后拉高 done 信号

module fft_core #(
    parameter FFT_LEN      = 1024,  // FFT 点数
    parameter FFT_OUT_WIDTH = 24    // FFT IP 输出每分量位宽（unscaled: 12+10=22, pad到24）
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] din,         // ADC 原始输出（Offset Binary 格式）
    input  wire        din_valid,   // 输入数据有效标志

    // 结果 RAM 读接口（供 uart_fft_sender 读取）
    input  wire [9:0]  rd_addr,
    output wire [23:0] rd_data,

    output reg         done         // FFT + 存储完成标志
);

    // =========================================================================
    // 状态机定义
    // =========================================================================
    localparam S_IDLE    = 3'd0;    // 等待首个有效样本
    localparam S_CONFIG  = 3'd1;    // 发送 FFT 配置字（forward）
    localparam S_COLLECT = 3'd2;    // 收集 1024 个样本送入 FFT IP
    localparam S_WAIT    = 3'd3;    // 等待 FFT IP 开始输出
    localparam S_STORE   = 3'd4;    // 接收 FFT 输出，计算幅值，写入 RAM
    localparam S_DONE    = 3'd5;    // 完成，停止

    reg [2:0] state;

    // =========================================================================
    // 输入格式转换：Offset Binary → 二进制补码 → 符号扩展到 16bit
    // =========================================================================
    wire signed [11:0] signed_din = {~din[11], din[10:0]};
    wire [15:0] fir_din_16 = {{4{signed_din[11]}}, signed_din};

    // FFT IP 输入：低16位=实部，高16位=虚部（=0）
    wire [31:0] fft_din = {16'b0, fir_din_16};

    // =========================================================================
    // 样本计数器
    // =========================================================================
    reg [9:0] sample_cnt;

    // =========================================================================
    // FFT IP AXI-Stream 接口信号
    // =========================================================================
    // 配置通道
    reg        s_axis_config_tvalid;
    wire       s_axis_config_tready;
    wire [7:0] s_axis_config_tdata = 8'b0000_0001; // bit[0]=1: forward FFT

    // 数据输入通道
    reg        s_axis_data_tvalid;
    wire       s_axis_data_tready;
    reg        s_axis_data_tlast;

    // 数据输出通道
    wire [47:0] m_axis_data_tdata;   // {imag[23:0], real[23:0]}
    wire        m_axis_data_tvalid;
    wire        m_axis_data_tlast;
    reg         m_axis_data_tready;

    // =========================================================================
    // 例化 Xilinx FFT IP
    // =========================================================================
    // 用户需在 Vivado IP Catalog 中配置：
    //   - Transform Length: 1024
    //   - Architecture: Radix-4, Burst I/O
    //   - Data Format: Fixed Point
    //   - Input Data Width: 12
    //   - Phase Factor Width: 16
    //   - Scaling: Unscaled
    //   - Output Ordering: Natural Order
    //   - 实例名: xfft_0
    xfft_0 u_fft (
        .aclk                        (clk),
        .aresetn                     (rst_n),
        // 配置通道
        .s_axis_config_tdata         (s_axis_config_tdata),
        .s_axis_config_tvalid        (s_axis_config_tvalid),
        .s_axis_config_tready        (s_axis_config_tready),
        // 数据输入
        .s_axis_data_tdata           (fft_din),
        .s_axis_data_tvalid          (s_axis_data_tvalid),
        .s_axis_data_tready          (s_axis_data_tready),
        .s_axis_data_tlast           (s_axis_data_tlast),
        // 数据输出
        .m_axis_data_tdata           (m_axis_data_tdata),
        .m_axis_data_tvalid          (m_axis_data_tvalid),
        .m_axis_data_tlast           (m_axis_data_tlast),
        .m_axis_data_tready          (m_axis_data_tready),
        // 事件（不使用）
        .event_frame_started         (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_data_in_channel_halt  (),
        .event_status_channel_halt   (),
        .event_data_out_channel_halt ()
    );

    // =========================================================================
    // 幅值计算：alpha-max-beta-min 近似
    // =========================================================================
    // mag ≈ max(|re|, |im|) + min(|re|, |im|) / 4
    // 最大误差 ≈ 11.8%，无需 DSP
    wire signed [FFT_OUT_WIDTH-1:0] fft_re = m_axis_data_tdata[FFT_OUT_WIDTH-1:0];
    wire signed [FFT_OUT_WIDTH-1:0] fft_im = m_axis_data_tdata[FFT_OUT_WIDTH+24-1:24];

    // 取绝对值
    wire [FFT_OUT_WIDTH-1:0] abs_re = fft_re[FFT_OUT_WIDTH-1] ? (~fft_re + 1'b1) : fft_re;
    wire [FFT_OUT_WIDTH-1:0] abs_im = fft_im[FFT_OUT_WIDTH-1] ? (~fft_im + 1'b1) : fft_im;

    // max 和 min
    wire [FFT_OUT_WIDTH-1:0] max_val = (abs_re >= abs_im) ? abs_re : abs_im;
    wire [FFT_OUT_WIDTH-1:0] min_val = (abs_re >= abs_im) ? abs_im : abs_re;

    // 幅值近似：max + min/4
    wire [23:0] magnitude = max_val[23:0] + {2'b0, min_val[23:2]};

    // =========================================================================
    // 结果 RAM：1024 x 24-bit 简单双口
    // =========================================================================
    reg [23:0] result_ram [0:FFT_LEN-1];
    reg [9:0]  wr_addr;

    // 写端口
    always @(posedge clk) begin
        if (state == S_STORE && m_axis_data_tvalid && m_axis_data_tready)
            result_ram[wr_addr] <= magnitude;
    end

    // 读端口
    reg [23:0] rd_data_reg;
    always @(posedge clk) begin
        rd_data_reg <= result_ram[rd_addr];
    end
    assign rd_data = rd_data_reg;

    // =========================================================================
    // 主状态机
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= S_IDLE;
            sample_cnt           <= 10'd0;
            wr_addr              <= 10'd0;
            done                 <= 1'b0;
            s_axis_config_tvalid <= 1'b0;
            s_axis_data_tvalid   <= 1'b0;
            s_axis_data_tlast    <= 1'b0;
            m_axis_data_tready   <= 1'b0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    done <= 1'b0;
                    // 等待第一个有效 ADC 样本
                    if (din_valid) begin
                        state                <= S_CONFIG;
                        s_axis_config_tvalid <= 1'b1;
                    end
                end

                // ---------------------------------------------------------
                S_CONFIG: begin
                    // 发送 FFT 配置字（forward）
                    if (s_axis_config_tready) begin
                        s_axis_config_tvalid <= 1'b0;
                        state                <= S_COLLECT;
                        // 第一个样本已经在 din 上，直接送入
                        s_axis_data_tvalid   <= 1'b1;
                        sample_cnt           <= 10'd1;
                        s_axis_data_tlast    <= 1'b0;
                    end
                end

                // ---------------------------------------------------------
                S_COLLECT: begin
                    // 收集 1024 个样本送入 FFT IP
                    if (din_valid && s_axis_data_tready) begin
                        sample_cnt <= sample_cnt + 1'b1;

                        if (sample_cnt == FFT_LEN - 2)
                            s_axis_data_tlast <= 1'b1;

                        if (sample_cnt == FFT_LEN - 1) begin
                            // 最后一个样本已发送
                            s_axis_data_tvalid <= 1'b0;
                            s_axis_data_tlast  <= 1'b0;
                            m_axis_data_tready <= 1'b1;
                            state              <= S_WAIT;
                        end
                    end

                    // 仅在有新数据时拉高 tvalid
                    s_axis_data_tvalid <= din_valid;
                end

                // ---------------------------------------------------------
                S_WAIT: begin
                    // 等待 FFT IP 开始输出
                    if (m_axis_data_tvalid) begin
                        state   <= S_STORE;
                        wr_addr <= 10'd0;
                    end
                end

                // ---------------------------------------------------------
                S_STORE: begin
                    // 接收 FFT 输出，计算幅值，写入 RAM
                    if (m_axis_data_tvalid && m_axis_data_tready) begin
                        wr_addr <= wr_addr + 1'b1;

                        if (m_axis_data_tlast) begin
                            m_axis_data_tready <= 1'b0;
                            done               <= 1'b1;
                            state              <= S_DONE;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    // done 保持一拍后回到 IDLE，可被再次触发
                    done       <= 1'b0;
                    sample_cnt <= 10'd0;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
