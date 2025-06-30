; 输入解析 (在 GetNextToken 中)
TokenIsNumber:
    invoke crt_atof, esi      ; 将字符串转换为 REAL8 浮点数
    fstp   currentTokenVal   ; 存入临时变量，最终会压入FPU栈顶

; 硬件计算 (在 PerformCalculation 的 RPN 求值部分)
fld     op1                 ; 加载操作数1到 ST(0)
fld     op2                 ; 加载操作数2到 ST(0), op1移动到 ST(1)
; ...
faddp   st(1), st(0)        ; 加法: ST(1) = ST(1) + ST(0), 弹出ST(0)
fsubp   st(1), st(0)        ; 减法: ST(1) = ST(1) - ST(0), 弹出ST(0)
fmulp   st(1), st(0)        ; 乘法: ST(1) = ST(1) * ST(0), 弹出ST(0)
fdivp   st(1), st(0)        ; 除法: ST(1) = ST(1) / ST(0), 弹出ST(0)

; 结果输出 (在 PerformCalculation 的末尾)
fstp    tempResult          ; 从FPU栈顶弹出最终结果到内存
invoke  crt_printf, addr szResultFmt, tempResult ; 调用C库函数格式化输出