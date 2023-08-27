module tb;

    reg clock, reset_b, start;

    wire [15:0] count, q, random;
    wire seed_pulse;

    reg [3:0] in_value1, in_value2, in_value3;
    reg [6:0] in_money;
    wire [3:0] out_random3, out_random2, out_random1;
    wire [9:0] out_money;

    slot_machine sm1 (clock, start, reset_b, in_value1, in_value2, in_value3, in_money, out_random3, out_random2, out_random1, out_money);

    counter c1 (clock, reset_b, start, count, seed_pulse);
    lfsr c2 (clock, reset_b, seed_pulse, count, q);
    random c3 (clock, reset_b, start, q, random);

    initial
    clock = 0;
    always
    #5 clock = ~clock;

    initial
    begin
        reset_b = 0; // 0
        #10 reset_b =1; //10
        #380 reset_b = 0;
    end

    initial
    begin
        start = 0;
        #40 start =1;
        #100 start = 0;
        #80 start =1;
        #100 start = 0;
        #50 start = 1;
        #55 $finish;
    end

    initial
    begin
        in_value3 = 4'd1; in_value2 = 4'd3; in_value1 = 4'd4;
        #20 in_value3 = 4'd2; in_value2 = 4'd3; in_value1 = 4'd4;
        #70 in_value3 = 4'd2; in_value2 = 4'd3; in_value1 = 4'd4;
        #70 in_value3 = 4'd4; in_value2 = 4'd2; in_value1 = 4'd1;
        #100 in_value3 = 4'd4; in_value2 = 4'd4; in_value1 = 4'd1;
        #100 in_value3 = 4'd2; in_value2 = 4'd0; in_value1 = 4'd1;
    end

    initial
    begin
        in_money = 7'b1110;
        #10 in_money = 7'b11010;
        #30 in_money = 7'b111_1111;
        #20 in_money = 7'b1_1011;
        #10 in_money = 7'b0;
        #90 in_money = 7'b110;
        #20 in_money = 7'b1_1011;
        #60 in_money = 7'b0;
        #150 in_money = 7'b110;
    end

    initial
    $monitor("time:%3d  ||  start: %b, reset_b: %b, state: S%d  ||  count: %d  ||  lfsr: %b, random: %d  ||  BCD: %d, %d, %d, in_value: %d, %d, %d  ||  in_money: %d  ->  out_money: %d  ||", $time, start, reset_b, sm1.state, count, q, random, out_random3, out_random2, out_random1, in_value3, in_value2, in_value1, in_money, out_money);
endmodule

module slot_machine (clock, start, reset_b, in_value1, in_value2, in_value3, in_money, out_random3, out_random2, out_random1, out_money);
    input wire clock, start, reset_b;
    input wire [3:0] in_value1, in_value2, in_value3;
    input wire [6:0] in_money;
    output wire [3:0] out_random3, out_random2, out_random1; // BCD의 5자리 중 뒷 3자리만 사용
    output reg [9:0] out_money;

    // connection
    reg [2:0] state;
    reg [2:0] next_state;
    reg [6:0] memory_in_money;
    reg memory_in_money_pushed;

    // parameter
    parameter S0 = 2'd0, S1 = 2'd1, S2 = 2'd2, S3 = 2'd3;

    // wire
    wire [15:0] random;
    wire [15:0] q; // lfsr 모듈의 출력값, random 모듈의 입력값
    wire seed_pulse; // 1bit짜리 seed pulse => clock 모듈에서 나오는 값 "한번만 실행할 때를 나타냄"
    wire [15:0] count; // counter 모듈의 count값으로 lfsr의 seed로 사용
    wire [3:0] digit1000, digit10000; //남은 값들 (BCD 1000자리, 10000자리 값들)

    // 파생
    random r1 (clock, reset_b, start, q, random);
    lfsr l1 (clock, reset_b, seed_pulse, count, q);
    counter c1 (clock, reset_b, start, count, seed_pulse);
    // binary_to_BCD 파생: ramdom 모듈의 16비트 random값을 받아 BCD 5자리 추출
    binary_to_BCD btb1 (.binary(random), .digit10000(digit10000), .digit1000(digit1000), .digit100(out_random3), .digit10(out_random2), .digit0(out_random1));


    // 클럭의 상승엣지에서만 작동됨 reset_b에 1이 들어오면 언제든지 초기화
    always @ (posedge clock, negedge reset_b)
    begin
        if (~reset_b) // reset_b:0 -> 상태 초기화
            state <= S0;
        else // 일반적으로 state가 다음 state로 변경
            state <= next_state;
    end

    // start:1 이고 1<=in_money<=100일때의 in_money를 memory_in_money에 단 한번 저장
    always @(posedge clock, negedge reset_b)
    begin
        if (~reset_b) begin
            memory_in_money_pushed <= 1'b0;
            memory_in_money <= 7'b0;
        end
        else if ((in_money >= 7'd1 & in_money <= 7'd100) & random == 0 & ~memory_in_money_pushed & start) begin
            memory_in_money_pushed <= 1'b1;
            memory_in_money <= in_money;

        end
        else if (~start) begin
            memory_in_money_pushed <= 1'b0;
            memory_in_money <= 7'b0;
        end
    end

    // 상태천이를 위한 기술
    always @ (*)
    begin
        case(state)
            S0: begin
                if (~start) begin
                    out_money <= in_money;
                    next_state <= S0;
                end
                else begin // start: 1
                    out_money <= in_money;
                    next_state <= S1;
                end
            end

            S1: begin
                if (random != 0)begin
                    next_state <= S2; // random값이 들어와야 S2로 넘어감
                end
                else if (in_money == 0 | in_money > 7'd100 & random == 0) begin // 1~100의 머니가 들어오지 않았을때
                    next_state <= S1;
                    out_money <= in_money;
                end
                else if ((in_money >= 7'd1 & in_money <= 7'd100) & random == 0) begin // 1~100의 머니이고 random이 0일때 
                    out_money <= 1'b0;
                    next_state <= S1;
                end

            end

            S2: begin
                if (out_random3 == in_value3 & out_random2 == in_value2 & out_random1 == in_value1) begin
                    out_money <= 4'b1010 * memory_in_money;
                    next_state <= S3;
                end
                else if ((out_random3 == in_value3 & out_random2 == in_value2) | (out_random3 == in_value3 & out_random1 == in_value1) | (out_random2 == in_value2 & out_random1 == in_value1)) begin
                    out_money <= 4'b101 * memory_in_money;
                    next_state <= S3;
                end
                else if (out_random3 == in_value3 | out_random2 == in_value2 | out_random1 == in_value1) begin
                    out_money <= 2'b10 * memory_in_money;
                    next_state <= S3;
                end
                else begin
                    out_money <= 1'b0 * memory_in_money;
                    next_state <= S3;
                end
            end
            S3: begin // start가 1일때 S0으로 가는 것을 방지
                if (~start) // start:0 -> S0으로 이동
                    next_state <= S0;
                else begin
                    next_state <= S3;
                    out_money <= 7'b0;
                end
            end
            default state <= S0;
        endcase
    end
endmodule

// ★★★★★ random 생성 ★★★★★
module random (clock, reset_b, start, q, random);
    input wire clock, reset_b, start;
    input wire [15:0] q;
    output reg [15:0] random; //출력

    parameter magic = 16'd6; // 몇번 lfsr에서 돌려줄지 결정

    reg [15:0] count;
    reg randomed;

    always @(posedge clock, negedge reset_b)
    begin
        if (~reset_b) begin
            count <= 16'b0;
            random <= 16'b0;
            randomed <= 1'b0;
        end
        else if (~start) begin // start:0 random값은 0으로 초기화
            count <= 16'b0;
            random <= 16'b0;
            randomed <= 1'b0;
        end
        else if (start & (count == magic) & ~randomed) begin // randomed:0 start:1 count:7  random값이 lfsr의 q로 초기화, count값 유지, randomed가 1이 되기에 더 이상 이 루프로 들어올 수 없음
            count <= count;
            random <= q;
            randomed <= 1'b1;
        end
        else begin // randomed:1    유지, count + 1 증가
            count <= count + 1;
            random <= random;
            randomed <= randomed;
        end
    end
endmodule

// ★★★★★ 16bit lfsr register ★★★★★
module lfsr (clock, reset_b, seed_pulse, count, q);
    input wire clock, reset_b, seed_pulse; // seed_pulse: seed를 딱 한번만 주기 위해 사용
    input wire [15:0] count;

    output wire [15:0] q;

    reg [15:0] r_reg;
    wire [15:0] r_next;
    wire feedback_value;

    always @(posedge clock, negedge reset_b)
    begin
        if (~reset_b)
            r_reg <= 16'b1;
        else if (seed_pulse)
            r_reg <= count;
        else
            r_reg <= r_next;
    end

    assign feedback_value = r_reg[13] ^ r_reg[4] ^ r_reg[0]; //lfsr의 섞어주는 기능

    assign r_next = {feedback_value, r_reg[15:1]};
    assign q = r_reg;
endmodule

// ★★★★★ 16bit counter ★★★★★
module counter (clock, reset_b, start, count, seed_pulse);
    input wire clock, reset_b, start;
    output reg [15:0] count;
    output reg seed_pulse;

    always @(posedge clock, negedge reset_b)
    begin
        if (~reset_b)
            count <= 16'b0;
        else
            count <= count + 1;
    end

    reg pushed;

    // 딱한번만 줄때 유용하게 사용  
    // pushed 값 설정 <start가 0이 되기 전까지 1을 유지, start가 0이되면 pushed를 0으로 만듦>
    always @(posedge clock, negedge reset_b)
    begin
        if (~reset_b)
            pushed <= 1'b0;
        else if (~pushed & start)
            pushed <= 1'b1;
        else if (~start)
            pushed <= 1'b0;
    end

    // seed_pulse의 생성  => start가 1이 될때 딱 한번만 seed_pulse는 1이 되며, 다를 때는 0유지
    always @(posedge clock, negedge reset_b)
    begin
        if (~reset_b) // reset:1
            seed_pulse <= 1'b0;
        else if (~pushed & start) // pushed:0 start:1  => start가 0에서 1로 바뀔때, pushed는 0이므로 딱 한번 발생
            seed_pulse <= 1'b1;
        else // pushed:1
            seed_pulse <= 1'b0;
    end
endmodule

// ★★★★★ 16bit binary to BCD ★★★★★
module binary_to_BCD(binary, digit10000, digit1000, digit100, digit10, digit0);
    input [15:0] binary;
    output reg [3:0] digit10000, digit1000, digit100, digit10, digit0;
    wire [3:0] c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19,c20,c21,c22,c23,c24,c25,c26,c27,c28,c29,c30,c31,c32,c33,c34; // add3's output
    reg [3:0] d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13,d14,d15,d16,d17,d18,d19,d20,d21,d22,d23,d24,d25,d26,d27,d28,d29,d30,d31,d32,d33,d34; // add3's input

    add3 a1(d1,c1); add3 a2(d2,c2); add3 a3(d3,c3); add3 a4(d4,c4); add3 a5(d5,c5);
    add3 a6(d6,c6); add3 a7(d7,c7); add3 a8(d8,c8); add3 a9(d9,c9); add3 a10(d10,c10);
    add3 a11(d11,c11); add3 a12(d12,c12); add3 a13(d13,c13); add3 a14(d14,c14); add3 a15(d15,c15);
    add3 a16(d16,c16); add3 a17(d17,c17); add3 a18(d18,c18); add3 a19(d19,c19); add3 a20(d20,c20);
    add3 a21(d21,c21); add3 a22(d22,c22); add3 a23(d23,c23); add3 a24(d24,c24); add3 a25(d25,c25);
    add3 a26(d26,c26); add3 a27(d27,c27); add3 a28(d28,c28); add3 a29(d29,c29); add3 a30(d30,c30);
    add3 a31(d31,c31); add3 a32(d32,c32); add3 a33(d33,c33); add3 a34(d34,c34);

    always @ (*) begin
        // 1st vertical line from right
        d1 <= {1'b0, binary[15:13]};
        d2 <= {c1[2:0], binary[12]};
        d3 <= {c2[2:0], binary[11]};
        d4 <= {c3[2:0], binary[10]};
        d5 <= {c4[2:0], binary[9]};
        d6 <= {c5[2:0], binary[8]};
        d7 <= {c6[2:0], binary[7]};
        d8 <= {c7[2:0], binary[6]};
        d9 <= {c8[2:0], binary[5]};
        d10 <= {c9[2:0], binary[4]};
        d11 <= {c10[2:0], binary[3]};
        d12 <= {c11[2:0], binary[2]};
        d13 <= {c12[2:0], binary[1]};

        // 2nd vertical line from right
        d14 <= {1'b0, c1[3], c2[3], c3[3]};
        d15 <= {c14[2:0], c4[3]};
        d16 <= {c15[2:0], c5[3]};
        d17 <= {c16[2:0], c6[3]};
        d18 <= {c17[2:0], c7[3]};
        d19 <= {c18[2:0], c8[3]};
        d20 <= {c19[2:0], c9[3]};
        d21 <= {c20[2:0], c10[3]};
        d22 <= {c21[2:0], c11[3]};
        d23 <= {c22[2:0], c12[3]};

        // 3rd vertical line from right
        d24 <= {1'b0, c14[3], c15[3], c16[3]};
        d25 <= {c24[2:0], c17[3]};
        d26 <= {c25[2:0], c18[3]};
        d27 <= {c26[2:0], c19[3]};
        d28 <= {c27[2:0], c20[3]};
        d29 <= {c28[2:0], c21[3]};
        d30 <= {c29[2:0], c22[3]};

        // 4th vertical line from right
        d31 <= {1'b0, c24[3], c25[3], c26[3]};
        d32 <= {c31[2:0], c27[3]};
        d33 <= {c32[2:0], c28[3]};
        d34 <= {c33[2:0], c29[3]};

        // output
        digit0 <= {c13[2:0], binary[0]};
        digit10 <= {c23[2:0], c13[3]};
        digit100 <= {c30[2:0], c23[3]};
        digit1000 <= {c34[2:0], c30[3]};
        digit10000 <= {c31[3], c32[3], c33[3], c34[3]};
    end
endmodule

// ★★★★★ adder for 'binary to BCD' ★★★★★
module add3(in,out);
    input [3:0] in;
    output [3:0] out;
    reg [3:0] out;

    always @ (in)
    case (in)
        4'b0000: out <= 4'b0000;
        4'b0001: out <= 4'b0001;
        4'b0010: out <= 4'b0010;
        4'b0011: out <= 4'b0011;
        4'b0100: out <= 4'b0100;
        4'b0101: out <= 4'b1000;
        4'b0110: out <= 4'b1001;
        4'b0111: out <= 4'b1010;
        4'b1000: out <= 4'b1011;
        4'b1001: out <= 4'b1100;
        default: out <= 4'b0000;
    endcase
endmodule
