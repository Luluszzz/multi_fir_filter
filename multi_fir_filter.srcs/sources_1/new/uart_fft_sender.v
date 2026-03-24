// UART FFT 结果发送模块
// 功能：从 FFT 结果 RAM 读取幅值数据，格式化为 FireWater ASCII 协议，逐字节发送
// 格式：每行 "channels: <index>,<magnitude>\n"
// 发送全部 1024 个频点后停止

module uart_fft_sender #(
    parameter FFT_LEN = 1024    // FFT 点数
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // 启动信号（fft_core.done）

    // FFT 结果 RAM 读接口
    output reg  [9:0]  fft_rd_addr,
    input  wire [23:0] fft_rd_data,

    // uart_tx 接口
    output reg  [7:0]  tx_data,
    output reg         tx_data_valid,
    input  wire        tx_data_ready,

    output reg         done            // 全部发送完成
);

    // =========================================================================
    // 状态机定义
    // =========================================================================
    localparam S_IDLE        = 4'd0;
    localparam S_READ_RAM    = 4'd1;   // 发出读地址，等一拍
    localparam S_READ_WAIT   = 4'd2;   // 等待 RAM 数据返回
    localparam S_CONV_IDX    = 4'd3;   // 索引值 binary → BCD（double-dabble 移位中）
    localparam S_CONV_MAG    = 4'd4;   // 幅值 binary → BCD（double-dabble 移位中）
    localparam S_SEND_PREFIX = 4'd5;   // 发送 "channels: "
    localparam S_SEND_IDX    = 4'd6;   // 发送索引 ASCII
    localparam S_SEND_COMMA  = 4'd7;   // 发送 ','
    localparam S_SEND_MAG    = 4'd8;   // 发送幅值 ASCII
    localparam S_SEND_NL     = 4'd9;   // 发送 '\n'
    localparam S_NEXT        = 4'd10;  // 下一个频点
    localparam S_DONE        = 4'd11;

    reg [3:0] state;

    // =========================================================================
    // 当前频点索引
    // =========================================================================
    reg [9:0] point_idx;

    // =========================================================================
    // 前缀字符串 "channels: " (10 字节)
    // =========================================================================
    reg [3:0] prefix_idx;
    wire [7:0] prefix_char;

    function [7:0] get_prefix;
        input [3:0] idx;
        case (idx)
            4'd0:  get_prefix = "c";
            4'd1:  get_prefix = "h";
            4'd2:  get_prefix = "a";
            4'd3:  get_prefix = "n";
            4'd4:  get_prefix = "n";
            4'd5:  get_prefix = "e";
            4'd6:  get_prefix = "l";
            4'd7:  get_prefix = "s";
            4'd8:  get_prefix = ":";
            4'd9:  get_prefix = " ";
            default: get_prefix = 8'h00;
        endcase
    endfunction

    assign prefix_char = get_prefix(prefix_idx);

    // =========================================================================
    // Binary-to-BCD：Sequential Double-Dabble 算法
    // =========================================================================
    // 最大 24-bit 输入 → 8 个 BCD 位 → 24 个时钟周期
    reg [23:0] dab_bin;        // 移位寄存器（二进制输入）
    reg [31:0] dab_bcd;        // BCD 寄存器（8 个 BCD 位 × 4 bit）
    reg [4:0]  dab_cnt;        // 移位计数器（0~23）

    // Double-Dabble 一步：检查每个 BCD 位是否 ≥ 5，是则加 3
    wire [31:0] dab_bcd_adj;
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : bcd_adj
            wire [3:0] digit = dab_bcd[gi*4 +: 4];
            assign dab_bcd_adj[gi*4 +: 4] = (digit >= 4'd5) ? (digit + 4'd3) : digit;
        end
    endgenerate

    // BCD 转换结果：8 个 ASCII 数字（bcd_digit[0] = 最高位）
    wire [7:0] bcd_digit [0:7];
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : bcd_to_ascii
            assign bcd_digit[gi] = {4'h3, dab_bcd[(7-gi)*4 +: 4]};
        end
    endgenerate

    // =========================================================================
    // 索引和幅值的 BCD 缓存
    // =========================================================================
    reg [7:0] idx_digits [0:3];   // 索引最多 4 位（0~1023）
    reg [2:0] idx_len;            // 有效数字位数
    reg [2:0] idx_pos;            // 当前发送位置

    reg [7:0] mag_digits [0:7];   // 幅值最多 8 位
    reg [3:0] mag_len;            // 有效数字位数
    reg [3:0] mag_pos;            // 当前发送位置

    // 锁存的 RAM 读数据（在 S_READ_WAIT 时捕获）
    reg [23:0] mag_data_latch;

    // =========================================================================
    // start 上升沿检测
    // =========================================================================
    reg start_d;
    wire start_rise = start & ~start_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            start_d <= 1'b0;
        else
            start_d <= start;
    end

    // =========================================================================
    // 主状态机（唯一驱动源，包含 double-dabble 移位逻辑）
    // =========================================================================
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            point_idx     <= 10'd0;
            fft_rd_addr   <= 10'd0;
            tx_data       <= 8'd0;
            tx_data_valid <= 1'b0;
            done          <= 1'b0;
            prefix_idx    <= 4'd0;
            idx_pos       <= 3'd0;
            mag_pos       <= 4'd0;
            dab_bin       <= 24'd0;
            dab_bcd       <= 32'd0;
            dab_cnt       <= 5'd0;
            idx_len       <= 3'd0;
            mag_len       <= 4'd0;
            mag_data_latch <= 24'd0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    done <= 1'b0;
                    if (start_rise) begin
                        point_idx   <= 10'd0;
                        fft_rd_addr <= 10'd0;
                        state       <= S_READ_RAM;
                    end
                end

                // ---------------------------------------------------------
                S_READ_RAM: begin
                    // 读地址已设置，等一拍让 RAM 输出数据
                    state <= S_READ_WAIT;
                end

                // ---------------------------------------------------------
                S_READ_WAIT: begin
                    // 锁存 RAM 数据，启动索引 BCD 转换
                    mag_data_latch <= fft_rd_data;
                    dab_bin  <= {14'd0, point_idx};
                    dab_bcd  <= 32'd0;
                    dab_cnt  <= 5'd0;
                    state    <= S_CONV_IDX;
                end

                // ---------------------------------------------------------
                S_CONV_IDX: begin
                    if (dab_cnt == 5'd24) begin
                        // 转换完成，提取有效数字（跳过前导零）
                        begin : extract_idx
                            reg found;
                            found = 1'b0;
                            idx_len = 3'd0;
                            for (i = 4; i < 8; i = i + 1) begin
                                if (dab_bcd[(7-i)*4 +: 4] != 4'd0)
                                    found = 1'b1;
                                if (found || i == 7) begin
                                    idx_digits[idx_len] = bcd_digit[i];
                                    idx_len = idx_len + 1'b1;
                                end
                            end
                        end
                        idx_pos <= 3'd0;
                        // 启动幅值 BCD 转换
                        dab_bin <= mag_data_latch;
                        dab_bcd <= 32'd0;
                        dab_cnt <= 5'd0;
                        state   <= S_CONV_MAG;
                    end else begin
                        // Double-Dabble 一步：加3调整 → 左移 → 补最高位
                        dab_bcd <= {dab_bcd_adj[30:0], dab_bin[23]};
                        dab_bin <= {dab_bin[22:0], 1'b0};
                        dab_cnt <= dab_cnt + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                S_CONV_MAG: begin
                    if (dab_cnt == 5'd24) begin
                        // 转换完成，提取有效数字
                        begin : extract_mag
                            reg found;
                            found = 1'b0;
                            mag_len = 4'd0;
                            for (i = 0; i < 8; i = i + 1) begin
                                if (dab_bcd[(7-i)*4 +: 4] != 4'd0)
                                    found = 1'b1;
                                if (found || i == 7) begin
                                    mag_digits[mag_len] = bcd_digit[i];
                                    mag_len = mag_len + 1'b1;
                                end
                            end
                        end
                        mag_pos    <= 4'd0;
                        prefix_idx <= 4'd0;
                        state      <= S_SEND_PREFIX;
                    end else begin
                        dab_bcd <= {dab_bcd_adj[30:0], dab_bin[23]};
                        dab_bin <= {dab_bin[22:0], 1'b0};
                        dab_cnt <= dab_cnt + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                S_SEND_PREFIX: begin
                    if (tx_data_ready && !tx_data_valid) begin
                        tx_data       <= prefix_char;
                        tx_data_valid <= 1'b1;
                    end else if (tx_data_valid && tx_data_ready) begin
                        tx_data_valid <= 1'b0;
                        if (prefix_idx == 4'd9) begin
                            state <= S_SEND_IDX;
                        end else begin
                            prefix_idx <= prefix_idx + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_SEND_IDX: begin
                    if (tx_data_ready && !tx_data_valid) begin
                        tx_data       <= idx_digits[idx_pos];
                        tx_data_valid <= 1'b1;
                    end else if (tx_data_valid && tx_data_ready) begin
                        tx_data_valid <= 1'b0;
                        if (idx_pos == idx_len - 1) begin
                            state <= S_SEND_COMMA;
                        end else begin
                            idx_pos <= idx_pos + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_SEND_COMMA: begin
                    if (tx_data_ready && !tx_data_valid) begin
                        tx_data       <= ",";
                        tx_data_valid <= 1'b1;
                    end else if (tx_data_valid && tx_data_ready) begin
                        tx_data_valid <= 1'b0;
                        state         <= S_SEND_MAG;
                    end
                end

                // ---------------------------------------------------------
                S_SEND_MAG: begin
                    if (tx_data_ready && !tx_data_valid) begin
                        tx_data       <= mag_digits[mag_pos];
                        tx_data_valid <= 1'b1;
                    end else if (tx_data_valid && tx_data_ready) begin
                        tx_data_valid <= 1'b0;
                        if (mag_pos == mag_len - 1) begin
                            state <= S_SEND_NL;
                        end else begin
                            mag_pos <= mag_pos + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_SEND_NL: begin
                    if (tx_data_ready && !tx_data_valid) begin
                        tx_data       <= "\n";
                        tx_data_valid <= 1'b1;
                    end else if (tx_data_valid && tx_data_ready) begin
                        tx_data_valid <= 1'b0;
                        state         <= S_NEXT;
                    end
                end

                // ---------------------------------------------------------
                S_NEXT: begin
                    if (point_idx == FFT_LEN - 1) begin
                        done  <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        point_idx   <= point_idx + 1'b1;
                        fft_rd_addr <= point_idx + 1'b1;
                        state       <= S_READ_RAM;
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    // 回到 IDLE，可被下次 start 上升沿再次触发
                    done  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
