# Returns whether the given file is a .jl file and contains either a
# @test or a @testset macro
function is_test_script(file)
    if ismatch(r"(?i)\.jl$", file)
        src = open(readstring, file)
        pos = 1
        while !done(src, pos)
            expr, pos = parse(src, pos)
            if contains_test_macro(expr)
                return true
            end
        end
    end
    return false
end

function contains_test_macro(expr::Expr)
    if expr.head == :macrocall && in(expr.args[1], [Symbol("@test") Symbol("@testset")])
        return true
    end
    return any(e -> contains_test_macro(e), filter(a -> isa(a, Expr), expr.args))
end

root = "."
file_list = readdir(root)
for f in file_list
    @printf("%s: %s\n", is_test_script(joinpath(root, f)), f)
end
