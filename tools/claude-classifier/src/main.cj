package cangjie_teacher_claude_classifier

import cangjie_teacher.runClaudeClassifierAdapter

main(args:Array<String>):Int64 {
    let result=runClaudeClassifierAdapter(args)
    if(result.ok){0}else{eprintln("claude classifier blocked diagnostic=${result.diagnostic}");1}
}
