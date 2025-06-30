; ========== MASM 汇编四则运算计算器 ===========
; 主程序文件 Calculator.asm
; 功能：支持表达式计算、历史记录、历史组合、分页浏览等
; 依赖：MASM32 SDK
; =============================================

.386
.model flat, stdcall
option casemap:none

; ====== 包含头文件和库 ======
include F:\masm32\include\windows.inc
include F:\masm32\include\kernel32.inc
include F:\masm32\include\masm32.inc
include F:\masm32\include\msvcrt.inc
includelib F:\masm32\lib\kernel32.lib
includelib F:\masm32\lib\masm32.lib
includelib F:\masm32\lib\msvcrt.lib

_getch PROTO C ; 控制台等待按键

; ====== 记号类型常量定义 ======
TOKEN_TYPE_UNKNOWN 	equ 0 	; 未知
TOKEN_TYPE_NUMBER 	equ 1 	; 数字
TOKEN_TYPE_PLUS 	equ 2 	; 加号
TOKEN_TYPE_MINUS 	equ 3 	; 减号
TOKEN_TYPE_MULTIPLY 	equ 4 	; 乘号
TOKEN_TYPE_DIVIDE 	equ 5 	; 除号
TOKEN_TYPE_LPAREN 	equ 6 	; 左括号
TOKEN_TYPE_RPAREN 	equ 7 	; 右括号
TOKEN_TYPE_END 	equ 8 	; 结束
TOKEN_TYPE_ERROR 	equ 9 	; 错误
TOKEN_TYPE_UNARY_MINUS 	equ 10 	; 一元负号

PAGE_SIZE 	equ 10 	; 每页显示10条历史记录

; ====== 输出队列结构体（逆波兰表达式用） ======
OutputToken STRUCT
	tokenType 	DWORD 	? 	; 记号类型
	tokenValue 	REAL8 	? 	; 数值
OutputToken ENDS


; ====== 数据段：字符串与缓冲区 ======
.data
    szMenu           db              13, 10, "===================================", 13, 10
                     db              "|   MASM Arithmetic Calculator   |", 13, 10
                     db              "===================================", 13, 10
                     db              "| 1. Calculate Expression        |", 13, 10
                     db              "| 2. View History                |", 13, 10
                     db              "| 3. Combine From History        |", 13, 10
                     db              "| 4. Clear History               |", 13, 10
                     db              "| 5. Exit                        |", 13, 10
                     db              "===================================", 13, 10
                     db              "Please enter your choice (1-5): ", 0                                        ; 主菜单
    szMenuLen        equ             $ - szMenu - 1
    cInputBuffer     db              16 dup(0)                                                                    ; 菜单输入缓冲
    szPromptExpr     db              13, 10, "Enter expression: ", 0                                              ; 输入表达式提示
    szExprBuffer     db              512 dup(0)                                                                   ; 表达式输入缓冲
    szPressAnyKey    db              13, 10, "--- Press any key to continue ---", 0                               ; 按任意键继续
    szResultHeader   db              13, 10, "--- Calculation Result ---", 13, 10, 0                              ; 结果标题
    szResultFmt      db              "Result: %f", 13, 10, 0                                                      ; 结果格式
    szHistoryFile    db              "history.txt", 0                                                             ; 历史记录文件名
    szHistoryHeader  db              13, 10, "--- Calculation History ---", 13, 10, 0                             ; 历史标题
    szHistoryEmpty   db              "No history found.", 13, 10, 0                                               ; 无历史
    szHistoryCleared db              "History has been cleared.", 13, 10, 0                                       ; 清空提示
    szCRLF           db              13, 10                                                                       ; 换行
    szHistoryLineFmt db              "%d: %s", 0                                                                  ; 历史行格式
    szFileReadMode   db              "r", 0                                                                       ; 文件只读模式
    szCls            db              "cls", 0                                                                     ; 清屏命令
    szCombinePrompt  db              13, 10, "Enter two line numbers to combine and multiply (e.g., 2,5): ", 0    ; 组合提示
    szCombineFmt     db              "%d,%d", 0                                                                   ; 组合输入格式
    szInvalidSel     db              "Invalid selection or format. Please try again.", 13, 10, 0                  ; 选择无效
    szCombinedExpr   db              13, 10, "Combined expression: %s", 13, 10, 0                                 ; 组合表达式显示
    szParenOpen      db              "(", 0                                                                       ; 左括号
    szParenClose     db              ")", 0                                                                       ; 右括号
    szMultiplySign   db              " * ", 0                                                                     ; 乘号
    szStepHeader     db              13, 10, "--- Calculation Steps ---", 13, 10, 0                               ; 步骤标题
    szStepFmt        db              "  %s %s %s = %s", 13, 10, 0                                                 ; 步骤格式
    szStepUnaryFmt   db              "  neg(%s) = %s", 13, 10, 0                                                  ; 一元负号格式
    szFloatFmt       db              "%f", 0                                                                      ; 浮点数格式
    szOpPlus         db              "+", 0                                                                       ; 加号
    szOpMinus        db              "-", 0                                                                       ; 减号
    szOpMultiply     db              "*", 0                                                                       ; 乘号
    szOpDivide       db              "/", 0                                                                       ; 除号
    ; --- 新增: 用于翻页的字符串 ---
    szPageInfoFmt    db              13, 10, "--- Page %d / %d ---", 13, 10, 0                                    ; 分页信息
    szPagePrompt     db              "(N)ext, (P)revious, (E)xit to Menu: ", 0                                    ; 分页操作提示

.data?
    hConsoleOutput   dd              ?
    hConsoleInput    dd              ?
    dwCharsRead      dd              ?
    pCurrentChar     dd              ?
                     currentTokenVal REAL8 	?
                     outputQueue     OutputToken 	64 dup(<>)
    outputQueueSize  dd              ?
    operatorStack    dd              64 dup(?)
    opStackTop       dd              ?
    g_prevTokenType  dd              ?
    lineBuffer       db              256 dup(?)
    line1Buffer      db              256 dup(?)
    line2Buffer      db              256 dup(?)
    rpnStepStack     dd              64 dup(?)
    rpnStepStackTop  dd              ?
    stringPool       db              4096 dup(?)
    pStringPool      dd              ?

.code

    ; ========== 主程序入口 ===========
main proc
    ; 主循环流程:
    ;   清屏()
    ;   显示菜单()
    ;   choice = 读取输入()
    ;   根据选项跳转到对应函数
    ;   重复循环
                              invoke GetStdHandle, STD_OUTPUT_HANDLE
                              mov    hConsoleOutput, eax
                              invoke GetStdHandle, STD_INPUT_HANDLE
                              mov    hConsoleInput, eax

    ; 主菜单循环
    MainMenuLoop:             
                              invoke crt_system, addr szCls                                                                                            ; 清屏
                              invoke WriteConsoleA, hConsoleOutput, addr szMenu, szMenuLen, addr dwCharsRead, NULL                                     ; 显示菜单
                              push   edi
                              mov    edi, offset cInputBuffer
                              mov    ecx, sizeof cInputBuffer
                              xor    al, al
                              rep    stosb                                                                                                             ; 清空输入缓冲
                              pop    edi
                              invoke ReadConsoleA, hConsoleInput, addr cInputBuffer, sizeof cInputBuffer, addr dwCharsRead, NULL                       ; 读取用户输入
                              cmp    cInputBuffer[0], '1'
                              je     CallCalculate
                              cmp    cInputBuffer[0], '2'
                              je     CallViewHistory
                              cmp    cInputBuffer[0], '3'
                              je     CallCombineHistory
                              cmp    cInputBuffer[0], '4'
                              je     CallClearHistory
                              cmp    cInputBuffer[0], '5'
                              je     DoExit
                              jmp    MainMenuLoop

    ; 选择1：表达式计算
    CallCalculate:            
                              call   DoCalculate
                              jmp    MainMenuLoop

    ; 选择2：查看历史（分页）
    CallViewHistory:          
                              call   DoViewHistory
                              jmp    MainMenuLoop

    ; 选择3：历史组合运算
    CallCombineHistory:       
                              call   DoHistoryCalculation
                              jmp    MainMenuLoop

    ; 选择4：清空历史
    CallClearHistory:         
                              call   DoClearHistory
                              jmp    MainMenuLoop

    ; 选择5：退出
    DoExit:                   
                              invoke ExitProcess, 0
main endp


    ; ========== 保存表达式到历史文件 ===========
    ; 输入：szExprBuffer
    ; 过程：打开history.txt，移动到文件末尾，写入表达式，并追加换行符
SaveExpressionToFile proc uses edi
                              LOCAL  hFile:HANDLE
                              LOCAL  dwBytesWritten:DWORD
                              invoke CreateFile, addr szHistoryFile, GENERIC_WRITE, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL    ; 打开/创建文件
                              mov    hFile, eax
                              cmp    eax, INVALID_HANDLE_VALUE
                              je     SaveExit
                              invoke SetFilePointer, hFile, 0, NULL, FILE_END                                                                          ; 定位到文件末尾
                              mov    edi, offset szExprBuffer
                              mov    ecx, 0
    CountLoop:                
                              cmp    byte ptr [edi+ecx], 0
                              je     FoundEnd
                              cmp    byte ptr [edi+ecx], 13
                              je     FoundEnd
                              inc    ecx
                              jmp    CountLoop
    FoundEnd:                 
                              invoke WriteFile, hFile, addr szExprBuffer, ecx, addr dwBytesWritten, NULL                                               ; 写入表达式
                              invoke WriteFile, hFile, addr szCRLF, 2, addr dwBytesWritten, NULL                                                       ; 换行
                              invoke CloseHandle, hFile
    SaveExit:                 
                              ret
SaveExpressionToFile endp


    ; ========== 获取历史文件指定行内容 ===========
    ; nLine: 行号（1开始），pBuf: 输出缓冲
    ; 过程：逐行读取文件，直到找到目标行号，复制内容到缓冲区，并移除末尾的换行符
GetHistoryLine proc uses edi, nLine:DWORD, pBuf:PTR BYTE
                              LOCAL  pFile:DWORD
                              LOCAL  lineCounter:DWORD
                              invoke crt_fopen, addr szHistoryFile, addr szFileReadMode
                              mov    pFile, eax
                              test   eax, eax
                              jz     GetLineFail
                              mov    lineCounter, 1
    GetLineLoop:              
                              mov    eax, lineCounter
                              cmp    eax, nLine
                              je     FoundLine
                              invoke crt_fgets, addr lineBuffer, sizeof lineBuffer, pFile
                              test   eax, eax
                              jz     CloseAndFail
                              inc    lineCounter
                              jmp    GetLineLoop
    FoundLine:                
                              invoke crt_fgets, pBuf, 256, pFile
                              test   eax, eax
                              jz     CloseAndFail
                              invoke crt_strlen, pBuf
                              mov    edi, pBuf
                              cmp    eax, 0
                              je     EndRemoveNL
                              cmp    byte ptr [edi+eax-1], 10
                              jne    EndRemoveNL
                              mov    byte ptr [edi+eax-1], 0
                              dec    eax
                              cmp    eax, 0
                              je     EndRemoveNL
                              cmp    byte ptr [edi+eax-1], 13
                              jne    EndRemoveNL
                              mov    byte ptr [edi+eax-1], 0
    EndRemoveNL:              
                              invoke crt_fclose, pFile
                              mov    eax, 1
                              ret
    CloseAndFail:             
                              invoke crt_fclose, pFile
    GetLineFail:              
                              mov    eax, 0
                              ret
GetHistoryLine endp


    ; ========== 历史组合运算 ===========
    ; 过程：
    ; 1. 显示所有历史记录
    ; 2. 提示用户输入两个行号 (n1, n2)
    ; 3. 获取第n1行和第n2行的表达式 (expr1, expr2)
    ; 4. 构造新表达式 "(expr1) * (expr2)"
    ; 5. 调用计算函数执行计算
DoHistoryCalculation proc
                              LOCAL  selNum1:DWORD
                              LOCAL  selNum2:DWORD
                              call   DoViewHistory_DisplayOnly                                                                                         ; 显示全部历史（无分页）
                              invoke StdOut, addr szCombinePrompt                                                                                      ; 提示输入
                              invoke ReadConsoleA, hConsoleInput, addr cInputBuffer, sizeof cInputBuffer, addr dwCharsRead, NULL
                              invoke crt_sscanf, addr cInputBuffer, addr szCombineFmt, addr selNum1, addr selNum2                                      ; 解析输入
                              cmp    eax, 2
                              jne    InvalidSelection
                              invoke GetHistoryLine, selNum1, addr line1Buffer
                              test   eax, eax
                              jz     InvalidSelection
                              invoke GetHistoryLine, selNum2, addr line2Buffer
                              test   eax, eax
                              jz     InvalidSelection
    ; 构造 (A) * (B) 表达式
                              invoke crt_strcpy, addr szExprBuffer, addr szParenOpen
                              invoke crt_strcat, addr szExprBuffer, addr line1Buffer
                              invoke crt_strcat, addr szExprBuffer, addr szParenClose
                              invoke crt_strcat, addr szExprBuffer, addr szMultiplySign
                              invoke crt_strcat, addr szExprBuffer, addr szParenOpen
                              invoke crt_strcat, addr szExprBuffer, addr line2Buffer
                              invoke crt_strcat, addr szExprBuffer, addr szParenClose
                              invoke crt_printf, addr szCombinedExpr, addr szExprBuffer                                                                ; 显示组合表达式
                              call   PerformCalculation
                              jmp    CalcCombineExit
    InvalidSelection:         
                              invoke StdOut, addr szInvalidSel
    CalcCombineExit:          
                              invoke StdOut, addr szPressAnyKey
                              invoke _getch
                              ret
DoHistoryCalculation endp


    ; ========== 显示全部历史（无分页，供组合用） ===========
DoViewHistory_DisplayOnly proc
                              LOCAL  pFile:DWORD
                              LOCAL  lineNum:DWORD
                              invoke crt_system, addr szCls
                              invoke StdOut, addr szHistoryHeader
                              invoke crt_fopen, addr szHistoryFile, addr szFileReadMode
                              mov    pFile, eax
                              test   eax, eax
                              jz     HistoryIsEmpty
                              mov    lineNum, 0
    PrintLineLoop:            
                              invoke crt_fgets, addr lineBuffer, sizeof lineBuffer, pFile
                              test   eax, eax
                              jz     EndOfFile
                              inc    lineNum
                              mov    eax, lineNum
                              invoke crt_printf, addr szHistoryLineFmt, eax, addr lineBuffer
                              jmp    PrintLineLoop
    EndOfFile:                
                              invoke crt_fclose, pFile
                              ret
    HistoryIsEmpty:           
                              invoke StdOut, addr szHistoryEmpty
                              ret
DoViewHistory_DisplayOnly endp


    ; ========== 分页显示历史记录 ===========
    ; 过程：
    ; 1. 统计历史文件总行数 total_lines
    ; 2. 计算总页数 total_pages = ceil(total_lines / PAGE_SIZE)
    ; 3. 进入分页循环 [PagingLoop]
    ; 4. 根据 current_page 计算要跳过的行数，并显示当前页的记录
    ; 5. 显示分页信息和操作提示，等待用户按键
    ; 6. 'n' -> 下一页, 'p' -> 上一页, 'e' -> 退出
DoViewHistory proc uses ebx esi edi
                              LOCAL  pFile:DWORD
                              LOCAL  totalLines:DWORD
                              LOCAL  currentPage:DWORD
                              LOCAL  totalPages:DWORD
                              LOCAL  lineCounter:DWORD
                              LOCAL  linesToSkip:DWORD
                              LOCAL  linesToPrint:DWORD
                              LOCAL  charInput:DWORD

    ; 第一步：统计总行数
                              invoke crt_fopen, addr szHistoryFile, addr szFileReadMode
                              mov    pFile, eax
                              test   eax, eax
                              jz     HistoryIsEmpty
                              mov    totalLines, 0
    CountLinesLoop:           
                              invoke crt_fgets, addr lineBuffer, sizeof lineBuffer, pFile
                              test   eax, eax
                              jz     DoneCounting
                              inc    totalLines
                              jmp    CountLinesLoop
    DoneCounting:             
                              invoke crt_fclose, pFile
                              cmp    totalLines, 0
                              je     HistoryIsEmpty

    ; 第二步：计算总页数
                              mov    eax, totalLines
                              xor    edx, edx
                              mov    ebx, PAGE_SIZE
                              div    ebx
                              test   edx, edx
                              jz     NoRemainder
                              inc    eax
    NoRemainder:              
                              cmp    eax, 0
                              jne    PagesExist
                              mov    eax, 1
    PagesExist:               
                              mov    totalPages, eax
                              mov    currentPage, 1

    ; 第三步：分页主循环
    PagingLoop:               
                              invoke crt_system, addr szCls
                              invoke StdOut, addr szHistoryHeader

    ; 重新打开文件，跳转到当前页
                              invoke crt_fopen, addr szHistoryFile, addr szFileReadMode
                              mov    pFile, eax
                              test   eax, eax
                              jz     ExitPaging
                              mov    eax, currentPage
                              dec    eax
                              mov    ebx, PAGE_SIZE
                              mul    ebx
                              mov    linesToSkip, eax
                              mov    lineCounter, 0
    SkipLinesLoop:            
                              mov    eax, lineCounter
                              cmp    eax, linesToSkip
                              jge    DoneSkipping
                              invoke crt_fgets, addr lineBuffer, sizeof lineBuffer, pFile
                              inc    lineCounter
                              jmp    SkipLinesLoop
    DoneSkipping:             
                              mov    linesToPrint, 0
    PrintPageLoop:            
                              mov    eax, linesToPrint
                              cmp    eax, PAGE_SIZE
                              jge    DonePrintingPage
                              invoke crt_fgets, addr lineBuffer, sizeof lineBuffer, pFile
                              test   eax, eax
                              jz     DonePrintingPage
                              mov    eax, linesToSkip
                              add    eax, linesToPrint
                              inc    eax
                              invoke crt_printf, addr szHistoryLineFmt, eax, addr lineBuffer
                              inc    linesToPrint
                              jmp    PrintPageLoop
    DonePrintingPage:         
                              invoke crt_fclose, pFile
                              invoke crt_printf, addr szPageInfoFmt, currentPage, totalPages
                              invoke StdOut, addr szPagePrompt
                              invoke _getch
                              mov    charInput, eax
    ; 处理用户输入
                              cmp    al, 'e'
                              je     ExitPaging
                              cmp    al, 'E'
                              je     ExitPaging
                              cmp    al, 'n'
                              je     NextPage
                              cmp    al, 'N'
                              je     NextPage
                              cmp    al, 'p'
                              je     PrevPage
                              cmp    al, 'P'
                              je     PrevPage
                              jmp    PagingLoop
    NextPage:                 
                              mov    eax, currentPage
                              mov    ebx, totalPages
                              cmp    eax, ebx
                              jge    PagingLoop
                              inc    currentPage
                              jmp    PagingLoop
    PrevPage:                 
                              mov    eax, currentPage
                              cmp    eax, 1
                              jle    PagingLoop
                              dec    currentPage
                              jmp    PagingLoop
    HistoryIsEmpty:           
                              invoke StdOut, addr szHistoryEmpty
                              invoke StdOut, addr szPressAnyKey
                              invoke _getch
    ExitPaging:               
                              ret
DoViewHistory endp


    ; ========== 清空历史记录 ===========
DoClearHistory proc
                              invoke DeleteFile, addr szHistoryFile
                              invoke StdOut, addr szHistoryCleared
                              invoke StdOut, addr szPressAnyKey
                              invoke _getch
                              ret
DoClearHistory endp


    ; ========== 获取运算符优先级 ===========
    ; 返回：eax=优先级（1 代表 +-, 2 代表 */, 3 代表一元负号）
GetPrecedence proc
                              cmp    eax, TOKEN_TYPE_UNARY_MINUS
                              je     PrecedenceIs3
                              cmp    eax, TOKEN_TYPE_MULTIPLY
                              je     PrecedenceIs2
                              cmp    eax, TOKEN_TYPE_DIVIDE
                              je     PrecedenceIs2
                              cmp    eax, TOKEN_TYPE_PLUS
                              je     PrecedenceIs1
                              cmp    eax, TOKEN_TYPE_MINUS
                              je     PrecedenceIs1
                              xor    eax, eax
                              ret
    PrecedenceIs1:            
                              mov    eax, 1
                              ret
    PrecedenceIs2:            
                              mov    eax, 2
                              ret
    PrecedenceIs3:            
                              mov    eax, 3
                              ret
GetPrecedence endp


    ; ========== 计算表达式主流程 ===========
DoCalculate proc
                              invoke StdOut, addr szPromptExpr
                              push   edi
                              mov    edi, offset szExprBuffer
                              mov    ecx, sizeof szExprBuffer
                              xor    al, al
                              rep    stosb
                              pop    edi
                              invoke ReadConsoleA, hConsoleInput, addr szExprBuffer, sizeof szExprBuffer, addr dwCharsRead, NULL                       ; 读取表达式
                              call   PerformCalculation                                                                                                ; 计算并显示步骤
                              call   SaveExpressionToFile                                                                                              ; 保存到历史
                              invoke StdOut, addr szPressAnyKey
                              invoke _getch
                              ret
DoCalculate endp

PerformCalculation proc uses ebx esi edi
                              LOCAL  tempResult:REAL8
                              LOCAL  op1:REAL8
                              LOCAL  op2:REAL8
                              LOCAL  currentPrec:DWORD
                              LOCAL  stackPrec:DWORD
                              LOCAL  pOp1Str:DWORD
                              LOCAL  pOp2Str:DWORD
                              LOCAL  pResultStr:DWORD
                              LOCAL  pOperatorStr:DWORD

    ; 算法1: Shunting-Yard 调度场算法 (中缀表达式转后缀/逆波兰表达式)
    ; 过程: 遍历记号流，使用一个操作符栈来处理优先级，生成一个逆波兰表达式(RPN)队列
                              mov    pCurrentChar, offset szExprBuffer
                              mov    outputQueueSize, 0
                              mov    opStackTop, 0
                              mov    g_prevTokenType, TOKEN_TYPE_LPAREN
    ShuntingYardLoop:         
                              call   GetNextToken
                              mov    ebx, eax
                              cmp    ebx, TOKEN_TYPE_END
                              je     HandleEnd
                              push   ebx
                              mov    g_prevTokenType, ebx
                              pop    ebx
                              cmp    ebx, TOKEN_TYPE_NUMBER
                              je     HandleNumber
                              cmp    ebx, TOKEN_TYPE_LPAREN
                              je     HandleLParen
                              cmp    ebx, TOKEN_TYPE_RPAREN
                              je     HandleRParen
                              cmp    ebx, TOKEN_TYPE_ERROR
                              je     HandleEnd
    ; 处理操作符:
    HandleOperator:           
    ; 如果记号是操作符，则从栈中弹出优先级更高或相等的旧操作符到输出队列
                              mov    eax, ebx
                              call   GetPrecedence
                              mov    currentPrec, eax
    CheckStackTop:            
                              cmp    opStackTop, 0
                              je     EndCheckStackTop
                              mov    ecx, opStackTop
                              dec    ecx
                              mov    edx, operatorStack[ecx*4]
                              cmp    edx, TOKEN_TYPE_LPAREN
                              je     EndCheckStackTop
                              mov    eax, edx
                              call   GetPrecedence
                              mov    stackPrec, eax
                              mov    eax, stackPrec
                              cmp    eax, currentPrec
                              jb     EndCheckStackTop
                              mov    ecx, opStackTop
                              dec    ecx
                              mov    edx, operatorStack[ecx*4]
                              mov    opStackTop, ecx
                              mov    ecx, outputQueueSize
                              mov    eax, ecx
                              imul   eax, SIZEOF OutputToken
                              add    eax, offset outputQueue
                              mov    [eax].OutputToken.tokenType, edx
                              inc    ecx
                              mov    outputQueueSize, ecx
                              jmp    CheckStackTop
    EndCheckStackTop:         
    ; 将当前操作符压入栈
                              mov    ecx, opStackTop
                              mov    operatorStack[ecx*4], ebx
                              inc    ecx
                              mov    opStackTop, ecx
                              jmp    ShuntingYardLoop
    ; 处理数字:
    HandleNumber:             
    ; 如果记号是数字，则将其添加到输出队列
                              mov    ecx, outputQueueSize
                              mov    eax, ecx
                              imul   eax, SIZEOF OutputToken
                              add    eax, offset outputQueue
                              mov    [eax].OutputToken.tokenType, ebx
                              fld    currentTokenVal
                              fstp   [eax].OutputToken.tokenValue
                              inc    ecx
                              mov    outputQueueSize, ecx
                              jmp    ShuntingYardLoop
    ; 处理左括号:
    HandleLParen:             
    ; 如果记号是'('，则将其压入操作符栈
                              mov    ecx, opStackTop
                              mov    operatorStack[ecx*4], ebx
                              inc    ecx
                              mov    opStackTop, ecx
                              jmp    ShuntingYardLoop
    ; 处理右括号:
    HandleRParen:             
    ; 如果记号是')'，则从栈中弹出操作符到队列，直到遇到'('
    PopUntilLParen:           
                              cmp    opStackTop, 0
                              je     ShuntingYardLoop
                              mov    ecx, opStackTop
                              dec    ecx
                              mov    edx, operatorStack[ecx*4]
                              mov    opStackTop, ecx
                              cmp    edx, TOKEN_TYPE_LPAREN
                              je     ShuntingYardLoop
                              mov    ecx, outputQueueSize
                              mov    eax, ecx
                              imul   eax, SIZEOF OutputToken
                              add    eax, offset outputQueue
                              mov    [eax].OutputToken.tokenType, edx
                              inc    ecx
                              mov    outputQueueSize, ecx
                              jmp    PopUntilLParen
    ; 处理表达式结束:
    HandleEnd:                
    ; 处理完所有记号后，将栈中剩余的操作符全部弹出到队列
    PopAllOperators_Loop:     
                              cmp    opStackTop, 0
                              je     EndPopAllOperators
                              mov    ecx, opStackTop
                              dec    ecx
                              mov    edx, operatorStack[ecx*4]
                              mov    opStackTop, ecx
                              mov    ecx, outputQueueSize
                              mov    eax, ecx
                              imul   eax, SIZEOF OutputToken
                              add    eax, offset outputQueue
                              mov    [eax].OutputToken.tokenType, edx
                              inc    ecx
                              mov    outputQueueSize, ecx
                              jmp    PopAllOperators_Loop
    EndPopAllOperators:       

    ; 算法2: RPN (逆波兰表达式)求值
    ; 过程: 遍历RPN队列，遇到数字则压入操作数栈，遇到操作符则弹出操作数进行计算，结果再压回栈中。
    ; 同时，使用一个字符串栈来记录每一步的计算过程并打印。
                              invoke StdOut, addr szStepHeader
                              mov    rpnStepStackTop, 0
                              mov    pStringPool, offset stringPool

                              mov    ecx, 0
    EvaluateRpnLoop:          
                              cmp    ecx, outputQueueSize
                              jge    EndEvaluateRpnLoop
	
                              push   ecx

                              mov    esi, ecx
                              imul   esi, SIZEOF OutputToken
                              add    esi, offset outputQueue
                              mov    edx, [esi].OutputToken.tokenType

                              cmp    edx, TOKEN_TYPE_NUMBER
                              je     EvalNumber
                              cmp    edx, TOKEN_TYPE_UNARY_MINUS
                              je     EvalUnaryMinus
                              jmp    EvalBinaryOp

    ; 求值：数字
    EvalNumber:               
    ; RPN求值：如果记号是数字，则将其压入数值栈和字符串栈
                              fld    [esi].OutputToken.tokenValue
                              mov    edi, pStringPool
                              invoke crt_sprintf, edi, addr szFloatFmt, [esi].OutputToken.tokenValue
                              mov    ebx, rpnStepStackTop
                              mov    rpnStepStack[ebx*4], edi
                              inc    ebx
                              mov    rpnStepStackTop, ebx
                              invoke crt_strlen, edi
                              add    edi, eax
                              inc    edi
                              mov    pStringPool, edi
                              jmp    NextRpnTokenInEval

    ; 求值：一元负号
    EvalUnaryMinus:           
    ; RPN求值：如果是一元负号，弹出一个操作数，计算后将结果压栈
                              fstp   op1
                              mov    ebx, rpnStepStackTop
                              dec    ebx
                              mov    eax, rpnStepStack[ebx*4]
                              mov    pOp1Str, eax
                              mov    rpnStepStackTop, ebx

                              fld    op1
                              fchs
                              fstp   tempResult

                              mov    edi, pStringPool
                              invoke crt_sprintf, edi, addr szFloatFmt, tempResult
                              mov    pResultStr, edi
                              invoke crt_printf, addr szStepUnaryFmt, pOp1Str, pResultStr
	
                              fld    tempResult
                              mov    ebx, rpnStepStackTop
                              mov    rpnStepStack[ebx*4], edi
                              inc    ebx
                              mov    rpnStepStackTop, ebx
                              invoke crt_strlen, edi
                              add    edi, eax
                              inc    edi
                              mov    pStringPool, edi
                              jmp    NextRpnTokenInEval

    ; 求值：二元操作符
    EvalBinaryOp:             
    ; RPN求值：如果是二元操作符，弹出两个操作数，计算后将结果压栈
                              fstp   op2
                              fstp   op1
                              mov    ebx, rpnStepStackTop
                              dec    ebx
                              mov    eax, rpnStepStack[ebx*4]
                              mov    pOp2Str, eax
                              dec    ebx
                              mov    eax, rpnStepStack[ebx*4]
                              mov    pOp1Str, eax
                              mov    rpnStepStackTop, ebx
	
                              fld    op1
                              fld    op2
	
                              mov    eax, [esi].OutputToken.tokenType
                              cmp    eax, TOKEN_TYPE_PLUS
                              je     do_add
                              cmp    eax, TOKEN_TYPE_MINUS
                              je     do_sub
                              cmp    eax, TOKEN_TYPE_MULTIPLY
                              je     do_mul
	
                              mov    pOperatorStr, offset szOpDivide
                              fdivp  st(1), st(0)
                              jmp    calc_done

    do_add:                   
                              mov    pOperatorStr, offset szOpPlus
                              faddp  st(1), st(0)
                              jmp    calc_done
    do_sub:                   
                              mov    pOperatorStr, offset szOpMinus
                              fsubp  st(1), st(0)
                              jmp    calc_done
    do_mul:                   
                              mov    pOperatorStr, offset szOpMultiply
                              fmulp  st(1), st(0)
                              jmp    calc_done

    calc_done:                
                              fstp   tempResult
	
                              mov    edi, pStringPool
                              invoke crt_sprintf, edi, addr szFloatFmt, tempResult
                              mov    pResultStr, edi
	
                              invoke crt_printf, addr szStepFmt, pOp1Str, pOperatorStr, pOp2Str, pResultStr
	
                              fld    tempResult
                              mov    ebx, rpnStepStackTop
                              mov    rpnStepStack[ebx*4], edi
                              inc    ebx
                              mov    rpnStepStackTop, ebx
                              invoke crt_strlen, edi
                              add    edi, eax
                              inc    edi
                              mov    pStringPool, edi
                              jmp    NextRpnTokenInEval
	
    NextRpnTokenInEval:       
                              pop    ecx
                              inc    ecx
                              jmp    EvaluateRpnLoop
    EndEvaluateRpnLoop:       
                              invoke StdOut, addr szResultHeader
                              fstp   tempResult
                              invoke crt_printf, addr szResultFmt, tempResult
                              ret
PerformCalculation endp


GetNextToken proc
    ; 过程:
    ; 1. 跳过所有前导空白字符
    ; 2. 检查当前字符：
    ;   - 如果是数字或小数点，解析整个浮点数
    ;   - 如果是'-'，检查前一个记号类型以判断是'一元负号'还是'减号'
    ;   - 如果是其他操作符，返回对应类型
    ;   - 如果是文件末尾(0), 返回END
    ;   - 否则返回ERROR
    ; 3. 更新 pCurrentChar 指针指向下一个未处理字符
                              mov    esi, pCurrentChar
    SkipWhitespace:           
                              mov    al, byte ptr [esi]
                              cmp    al, ' '
                              je     AdvanceAndRepeat
                              cmp    al, 9
                              je     AdvanceAndRepeat
                              cmp    al, 10
                              je     AdvanceAndRepeat
                              cmp    al, 13
                              je     AdvanceAndRepeat
                              jmp    FoundNonWhitespace
    AdvanceAndRepeat:         
                              inc    esi
                              jmp    SkipWhitespace
    FoundNonWhitespace:       
                              cmp    byte ptr [esi], 0
                              je     TokenIsEnd
                              mov    bl, byte ptr [esi]
                              cmp    bl, '0'
                              jb     CheckOperators
                              cmp    bl, '9'
                              ja     CheckDecimalOrOperators
                              jmp    TokenIsNumber
    CheckDecimalOrOperators:  
                              cmp    bl, '.'
                              je     TokenIsNumber
    CheckOperators:           
                              cmp    bl, '+'
                              je     TokenIsPlus
                              cmp    bl, '-'
                              je     TokenIsMinus
                              cmp    bl, '*'
                              je     TokenIsMultiply
                              cmp    bl, '/'
                              je     TokenIsDivide
                              cmp    bl, '('
                              je     TokenIsLparen
                              cmp    bl, ')'
                              je     TokenIsRparen
                              jmp    TokenIsError
    TokenIsNumber:            
                              invoke crt_atof, esi
                              fstp   currentTokenVal
    FindEndOfNumber:          
                              mov    bl, byte ptr [esi]
                              cmp    bl, '0'
                              jl     NotADigitOrPeriod
                              cmp    bl, '9'
                              jg     NotADigitOrPeriod
                              jmp    IsPartOfNumber
    NotADigitOrPeriod:        
                              cmp    bl, '.'
                              jne    EndOfNumberFound
    IsPartOfNumber:           
                              inc    esi
                              jmp    FindEndOfNumber
    EndOfNumberFound:         
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_NUMBER
                              ret
    TokenIsPlus:              
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_PLUS
                              ret
    TokenIsMinus:             
    ; 区分一元负号和二元减号
                              mov    eax, g_prevTokenType
                              cmp    eax, TOKEN_TYPE_NUMBER
                              je     ReturnBinaryMinus
                              cmp    eax, TOKEN_TYPE_RPAREN
                              je     ReturnBinaryMinus
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_UNARY_MINUS
                              ret
    ReturnBinaryMinus:        
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_MINUS
                              ret
    TokenIsMultiply:          
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_MULTIPLY
                              ret
    TokenIsDivide:            
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_DIVIDE
                              ret
    TokenIsLparen:            
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_LPAREN
                              ret
    TokenIsRparen:            
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_RPAREN
                              ret
    TokenIsEnd:               
                              mov    eax, TOKEN_TYPE_END
                              ret
    TokenIsError:             
                              inc    esi
                              mov    pCurrentChar, esi
                              mov    eax, TOKEN_TYPE_ERROR
                              ret
GetNextToken endp
end main