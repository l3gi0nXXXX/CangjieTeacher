package cangjie_teacher

main(args: Array<String>): Int64 {
    if (args.size == 0 || args[0] == "help") {
        println("CangjieTeacher: validate contracts, run isolated teacher cases, and export sanitized knowledge candidates")
        return 0
    }
    println("unsupported command")
    return 2
}

