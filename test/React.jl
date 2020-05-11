using Test
using Pluto
import Pluto: Notebook, Client, run_reactive!, Cell, WorkspaceManager
import Distributed

ENV["PLUTO_WORKSPACE_USE_DISTRIBUTED"] = "false"

@testset "Reactivity" begin
    fakeclient = Client(:fake, nothing)
    Pluto.connectedclients[fakeclient.id] = fakeclient

    

    @testset "Basic $(parallel ? "distributed" : "single-process")" for parallel in [false, true]
        ENV["PLUTO_WORKSPACE_USE_DISTRIBUTED"] = string(parallel)

        notebook = Notebook([
        Cell("x = 1"),
        Cell("y = x"),
        Cell("f(x) = x + y"),
        Cell("f(4)"),

        Cell("""begin
            g(a) = x
            g(a,b) = y
        end"""),
        Cell("g(6) + g(6,6)"),

        Cell("import Distributed"),
        Cell("Distributed.myid()"),
    ])
        fakeclient.connected_notebook = notebook

        @test !haskey(WorkspaceManager.workspaces, notebook.uuid)

        run_reactive!(notebook, notebook.cells[1:2])
        @test notebook.cells[1].output_repr == notebook.cells[2].output_repr
        notebook.cells[1].code = "x = 12"
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[1].output_repr == notebook.cells[2].output_repr

        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[3].error_repr == nothing
    
        run_reactive!(notebook, notebook.cells[4])
        @test notebook.cells[4].output_repr == "16"
        @test notebook.cells[4].error_repr == nothing

        notebook.cells[1].code = "x = 912"
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[4].output_repr == "916"

        notebook.cells[3].code = "f(x) = x"
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[4].output_repr == "4"

        notebook.cells[1].code = "x = 1"
        notebook.cells[2].code = "y = 2"
        run_reactive!(notebook, notebook.cells[1:2])
        run_reactive!(notebook, notebook.cells[5:6])
        @test notebook.cells[5].error_repr == nothing
        @test notebook.cells[6].output_repr == "3"

        notebook.cells[2].code = "y = 1"
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[6].output_repr == "2"

        notebook.cells[1].code = "x = 2"
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[6].output_repr == "3"

        run_reactive!(notebook, notebook.cells[7:8])
        @test xor(parallel, notebook.cells[8].output_repr == string(Distributed.myid()))

        WorkspaceManager.unmake_workspace(notebook)
    end

    ENV["PLUTO_WORKSPACE_USE_DISTRIBUTED"] = "false"


# https://github.com/fonsp/Pluto.jl/issues/32
    @testset "Bad code" begin
        notebook = Notebook([
        Cell("a"),
        Cell("1 = 2")
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[1].error_repr !== nothing
        @test notebook.cells[2].error_repr !== nothing

        WorkspaceManager.unmake_workspace(notebook)
    end

    @testset "Mutliple assignments" begin
        notebook = Notebook([
        Cell("x = 1"),
        Cell("x = 2"),
        Cell("f(x) = 3"),
        Cell("f(x) = 4"),
        Cell("g(x) = 5"),
        Cell("g = 6"),
    ])
        fakeclient.connected_notebook = notebook
    

        run_reactive!(notebook, notebook.cells[1])
        run_reactive!(notebook, notebook.cells[2])
        @test occursin("Multiple", notebook.cells[1].error_repr)
        @test occursin("Multiple", notebook.cells[2].error_repr)
    
        notebook.cells[1].code = ""
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[1].error_repr == nothing
        @test notebook.cells[2].error_repr == nothing
    
    # https://github.com/fonsp/Pluto.jl/issues/26
        notebook.cells[1].code = "x = 1"
        run_reactive!(notebook, notebook.cells[1])
        notebook.cells[2].code = "x"
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[1].error_repr == nothing
        @test notebook.cells[2].error_repr == nothing

        run_reactive!(notebook, notebook.cells[3])
        run_reactive!(notebook, notebook.cells[4])
        @test occursin("Multiple", notebook.cells[3].error_repr)
        @test occursin("Multiple", notebook.cells[4].error_repr)
    
        notebook.cells[3].code = ""
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[3].error_repr == nothing
        @test notebook.cells[4].error_repr == nothing
    
        run_reactive!(notebook, notebook.cells[5])
        run_reactive!(notebook, notebook.cells[6])
        @test occursin("Multiple", notebook.cells[5].error_repr)
        @test occursin("Multiple", notebook.cells[6].error_repr)
    
        notebook.cells[5].code = ""
        run_reactive!(notebook, notebook.cells[5])
        @test notebook.cells[5].error_repr == nothing
    # @test_broken !occursin("redefinition of constant", notebook.cells[6].error_repr)

        WorkspaceManager.unmake_workspace(notebook)
    end

    @testset "Cyclic" begin
        notebook = Notebook([
        Cell("x = y"),
        Cell("y = x")
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])
        run_reactive!(notebook, notebook.cells[2])
        @test occursin("Cyclic reference", notebook.cells[1].error_repr)
        @test occursin("Cyclic reference", notebook.cells[2].error_repr)

        WorkspaceManager.unmake_workspace(notebook)
    end

    @testset "Variable deletion" begin
        notebook = Notebook([
        Cell("x = 1"),
        Cell("y = x")
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[1].output_repr == notebook.cells[2].output_repr
        notebook.cells[1].code = ""
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[1].output_repr == ""
        @test notebook.cells[1].error_repr == nothing
        @test notebook.cells[2].output_repr == nothing
        @test occursin("x not defined", notebook.cells[2].error_repr)

        WorkspaceManager.unmake_workspace(notebook)
    end

    @testset "Recursion" begin
        notebook = Notebook([
        Cell("f(n) = n * f(n-1)"),

        Cell("k = 1"),
        Cell("""begin
            g(n) = h(n-1) + k
            h(n) = n > 0 ? g(n-1) : 0
        end"""),

        Cell("h(4)"),
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])
        @test startswith(notebook.cells[1].output_repr, "f (generic function with ")
        @test notebook.cells[1].error_repr == nothing

        run_reactive!(notebook, notebook.cells[2:3])
        @test notebook.cells[2].error_repr == nothing
        @test notebook.cells[3].error_repr == nothing
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[3].error_repr == nothing

        run_reactive!(notebook, notebook.cells[4])
        @test notebook.cells[4].output_repr == "2"

        notebook.cells[2].code = "k = 2"
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[4].output_repr == "4"

        WorkspaceManager.unmake_workspace(notebook)
    end

    @testset "Variable cannot reference its previous value" begin
        notebook = Notebook([
        Cell("x = 3")
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])
        notebook.cells[1].code = "x = x + 1"
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[1].output_repr == nothing
        @test occursin("UndefVarError", notebook.cells[1].error_repr)

        WorkspaceManager.unmake_workspace(notebook)
    end

    notebook = Notebook([
    Cell("y = 1"),
    Cell("f(x) = x + y"),
    Cell("f(3)"),

    Cell("g(a,b) = a+b"),
    Cell("g(5,6)"),

    Cell("h(x::Int64) = x"),
    Cell("h(7)"),
    Cell("h(8.0)"),

    Cell("p(x) = 9"),
    Cell("p isa Function"),

    Cell("module Something
        export a
        a(x::String) = \"🐟\"
    end"),
    Cell("using .Something"),
    Cell("a(x::Int64) = x"),
    Cell("a(\"i am a \")"),
    Cell("a(15)"),
    
    Cell("module Different
        export b
        b(x::String) = \"🐟\"
    end"),
    Cell("import .Different: b"),
    Cell("b(x::Int64) = x"),
    Cell("b(\"i am a \")"),
    Cell("b(20)"),
    
    Cell("module Wow
        export c
        c(x::String) = \"🐟\"
    end"),
    Cell("begin
        import .Wow: c
        c(x::Int64) = x
    end"),
    Cell("c(\"i am a \")"),
    Cell("c(24)"),

    Cell("(25,:fish)"),
    Cell("begin
        import Base: show
        show(io::IO, x::Tuple) = write(io, \"🐟\")
    end"),

    Cell("Base.isodd(n::Integer) = \"🎈\""),
    Cell("Base.isodd(28)"),
    Cell("isodd(29)"),

    Cell("using Dates"),
    Cell("year(DateTime(31))"),
])
    fakeclient.connected_notebook = notebook

    @testset "Changing functions" begin

        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[2].error_repr == nothing

        run_reactive!(notebook, notebook.cells[1])
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[3].output_repr == "4"

        notebook.cells[1].code = "y = 2"
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[3].output_repr == "5"
        @test notebook.cells[2].error_repr == nothing

        notebook.cells[1].code = "y"
        run_reactive!(notebook, notebook.cells[1])
        @test occursin("UndefVarError", notebook.cells[1].error_repr)
        @test notebook.cells[2].error_repr == nothing
        @test occursin("UndefVarError", notebook.cells[3].error_repr)

        run_reactive!(notebook, notebook.cells[4])
        run_reactive!(notebook, notebook.cells[5])
        @test notebook.cells[5].output_repr == "11"

        notebook.cells[4].code = "g(a) = a+a"
        run_reactive!(notebook, notebook.cells[4])
        @test notebook.cells[4].error_repr == nothing
        @test notebook.cells[5].error_repr != nothing

        notebook.cells[5].code = "g(5)"
        run_reactive!(notebook, notebook.cells[5])
        @test notebook.cells[5].output_repr == "10"

        run_reactive!(notebook, notebook.cells[6])
        run_reactive!(notebook, notebook.cells[7])
        run_reactive!(notebook, notebook.cells[8])
        @test notebook.cells[6].error_repr == nothing
        @test notebook.cells[7].error_repr == nothing
        @test notebook.cells[8].error_repr != nothing
    
        notebook.cells[6].code = "h(x::Float64) = 2.0 * x"
        run_reactive!(notebook, notebook.cells[6])
        @test notebook.cells[6].error_repr == nothing
        @test notebook.cells[7].error_repr != nothing
        @test notebook.cells[8].error_repr == nothing

        run_reactive!(notebook, notebook.cells[9:10])
        @test notebook.cells[9].error_repr == nothing
        @test notebook.cells[10].output_repr == "true"

        notebook.cells[9].code = "p = p"
        run_reactive!(notebook, notebook.cells[9])
        @test occursin("UndefVarError", notebook.cells[9].error_repr)

        notebook.cells[9].code = "p = 9"
        run_reactive!(notebook, notebook.cells[9])
        @test notebook.cells[9].error_repr == nothing
        @test notebook.cells[10].output_repr == "false"
        
        notebook.cells[9].code = "p(x) = 9"
        run_reactive!(notebook, notebook.cells[9])
        @test notebook.cells[9].error_repr == nothing
        @test notebook.cells[10].output_repr == "true"
    end

    @testset "Extending imported functions" begin
        run_reactive!(notebook, notebook.cells[11:15])
        @test_broken notebook.cells[11].error_repr == nothing
        @test_broken notebook.cells[12].error_repr == nothing # multiple definitions for `Something` should be okay?
        @test notebook.cells[13].error_repr == nothing
        @test notebook.cells[14].error_repr != nothing # the definition for a was created before `a` was used, so it hides the `a` from `Something`
        @test notebook.cells[15].output_repr == "15"

        
        run_reactive!(notebook, notebook.cells[13:15])
        @test notebook.cells[13].error_repr == nothing
        @test notebook.cells[14].error_repr != nothing # the definition for a was created before `a` was used, so it hides the `a` from `Something`
        @test notebook.cells[15].output_repr == "15"

        run_reactive!(notebook, notebook.cells[16:20])
        @test notebook.cells[16].error_repr == nothing
        @test occursin("Multiple", notebook.cells[17].error_repr)
        @test occursin("Multiple", notebook.cells[18].error_repr)
        @test occursin("UndefVarError", notebook.cells[19].error_repr)
        @test occursin("UndefVarError", notebook.cells[20].error_repr)

        run_reactive!(notebook, notebook.cells[21:24])
        @test notebook.cells[21].error_repr == nothing
        @test notebook.cells[22].error_repr == nothing
        @test notebook.cells[23].error_repr == nothing
        @test notebook.cells[23].output_repr == "\"🐟\""
        @test notebook.cells[24].output_repr == "24"

        notebook.cells[22].code = "import .Wow: c"
        run_reactive!(notebook, notebook.cells[22])
        @test notebook.cells[22].error_repr == nothing
        @test notebook.cells[23].output_repr == "\"🐟\""
        @test notebook.cells[24].error_repr != nothing # the extension should no longer exist

        # https://github.com/fonsp/Pluto.jl/issues/59
        run_reactive!(notebook, notebook.cells[25])
        @test notebook.cells[25].output_repr == "(25, :fish)"
        run_reactive!(notebook, notebook.cells[26])
        @test_broken notebook.cells[25].output_repr == "🐟" # cell's don't automatically call `show` again when a new overload is defined - that's a minor issue
        run_reactive!(notebook, notebook.cells[25])
        @test notebook.cells[25].output_repr == "🐟"

        notebook.cells[26].code = ""
        run_reactive!(notebook, notebook.cells[26])
        run_reactive!(notebook, notebook.cells[25])
        @test notebook.cells[25].output_repr == "(25, :fish)"

        run_reactive!(notebook, notebook.cells[28:29])
        @test notebook.cells[28].output_repr == "false"
        @test notebook.cells[29].output_repr == "true"
        run_reactive!(notebook, notebook.cells[27])
        @test notebook.cells[28].output_repr == "\"🎈\""
        @test_broken notebook.cells[29].output_repr == "\"🎈\"" # adding the overload doesn't trigger automatic re-eval because `isodd` doesn't match `Base.isodd`
        run_reactive!(notebook, notebook.cells[28:29])
        @test notebook.cells[28].output_repr == "\"🎈\""
        @test notebook.cells[29].output_repr == "\"🎈\""

        notebook.cells[27].code = ""
        run_reactive!(notebook, notebook.cells[27])
        @test notebook.cells[28].output_repr == "false"
        @test_broken notebook.cells[29].output_repr == "true" # removing the overload doesn't trigger automatic re-eval because `isodd` doesn't match `Base.isodd`
        run_reactive!(notebook, notebook.cells[28:29])
        @test notebook.cells[28].output_repr == "false"
        @test notebook.cells[29].output_repr == "true"
    end

    @testset "Using external libraries" begin
        run_reactive!(notebook, notebook.cells[30:31])
        @test notebook.cells[30].error_repr == nothing
        @test notebook.cells[31].output_repr == "31"
        run_reactive!(notebook, notebook.cells[31])
        @test notebook.cells[31].output_repr == "31"

        notebook.cells[30].code = ""
        run_reactive!(notebook, notebook.cells[30:31])
        @test occursin("UndefVarError", notebook.cells[31].error_repr)
    end
    WorkspaceManager.unmake_workspace(notebook)

    @testset "Functional programming" begin
        notebook = Notebook([
            Cell("a = 1"),
            Cell("map(2:2) do val; (global a = val; 2*val) end |> last"),

            Cell("b = 3"),
            Cell("g = f"),
            Cell("f(x) = x + b"),
            Cell("g(6)"),

            Cell("h = [x -> x + b][1]"),
            Cell("h(8)"),
        ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1:2])
        @test occursin("Multiple definitions for a", notebook.cells[1].error_repr)
        @test occursin("Multiple definitions for a", notebook.cells[2].error_repr)

        notebook.cells[1].code = "a"
        run_reactive!(notebook, notebook.cells[1])
        @test notebook.cells[1].output_repr == "2"
        @test notebook.cells[2].output_repr == "4"

        run_reactive!(notebook, notebook.cells[3:6])
        @test notebook.cells[3].error_repr == nothing
        @test notebook.cells[4].error_repr == nothing
        @test notebook.cells[5].error_repr == nothing
        @test notebook.cells[6].error_repr == nothing
        @test notebook.cells[6].output_repr == "9"

        notebook.cells[3].code = "b = -3"
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[6].output_repr == "3"

        run_reactive!(notebook, notebook.cells[7:8])
        @test notebook.cells[7].error_repr == nothing
        @test notebook.cells[8].output_repr == "5"

        notebook.cells[3].code = "b = 3"
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[8].output_repr == "11"

        WorkspaceManager.unmake_workspace(notebook)
        
    end

    @testset "Immutable globals" begin
    # We currently have a slightly relaxed version of immutable globals:
    # globals can only be mutated/assigned _in a single cell_.
        notebook = Notebook([
        Cell("x = 1"),
        Cell("x = 2"),
        Cell("y = -3; y = 3"),
        Cell("z = 4"),
        Cell("let global z = 5 end"),
        Cell("w"),
        Cell("function f(x) global w = x end"),
        Cell("f(8)"),
        Cell("v"),
        Cell("function g(x) global v = x end; g(10)"),
        Cell("g(11)"),
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[1].output_repr == nothing
        @test notebook.cells[2].output_repr == nothing
        @test occursin("Multiple definitions for x", notebook.cells[1].error_repr)
        @test occursin("Multiple definitions for x", notebook.cells[1].error_repr)
    
        notebook.cells[2].code = "x + 1"
        run_reactive!(notebook, notebook.cells[2])
        @test notebook.cells[1].output_repr == "1"
        @test notebook.cells[2].output_repr == "2"
    
        run_reactive!(notebook, notebook.cells[3])
        @test notebook.cells[3].output_repr == "3"

        run_reactive!(notebook, notebook.cells[4])
        run_reactive!(notebook, notebook.cells[5])
        @test occursin("Multiple definitions for z", notebook.cells[4].error_repr)
        @test occursin("Multiple definitions for z", notebook.cells[5].error_repr)
    
        run_reactive!(notebook, notebook.cells[6:7])
        @test occursin("UndefVarError", notebook.cells[6].error_repr)
        @test notebook.cells[7].error_repr == nothing
    
        run_reactive!(notebook, notebook.cells[8])
        @test occursin("UndefVarError", notebook.cells[6].error_repr)
        @test occursin("Multiple definitions for w", notebook.cells[7].error_repr)
        @test occursin("Multiple definitions for w", notebook.cells[8].error_repr)

        run_reactive!(notebook, notebook.cells[9:10])
        @test notebook.cells[9].output_repr == "10"
        @test notebook.cells[10].error_repr == nothing

        run_reactive!(notebook, notebook.cells[11])
        @test occursin("UndefVarError", notebook.cells[9].error_repr)
        @test occursin("Multiple definitions for v", notebook.cells[10].error_repr)
        @test occursin("Multiple definitions for v", notebook.cells[11].error_repr)

        WorkspaceManager.unmake_workspace(notebook)
    end

    @testset "Run all" begin
        notebook = Notebook([
        Cell("x = []"),
        Cell("b = a + 2; push!(x,2)"),
        Cell("c = b + a; push!(x,3)"),
        Cell("a = 1; push!(x,4)"),
        Cell("a + b +c; push!(x,5)"),

        Cell("a = 1; push!(x,6)"),

        Cell("n = m; push!(x,7)"),
        Cell("m = n; push!(x,8)"),
        Cell("n = 1; push!(x,9)"),

        Cell("push!(x,10)"),
        Cell("push!(x,11)"),
        Cell("push!(x,12)"),
        Cell("push!(x,13)"),
        Cell("push!(x,14)"),

        Cell("join(x, '-')"),

        Cell("φ(16)"),
        Cell("φ(χ) = χ + υ"),
        Cell("υ = 18"),

        Cell("f(19)"),
        Cell("f(x) = x + g(x)"),
        Cell("g(x) = x + y"),
        Cell("y = 22"),
    ])
        fakeclient.connected_notebook = notebook

        run_reactive!(notebook, notebook.cells[1])

        @testset "Basic" begin
            run_reactive!(notebook, notebook.cells[2:5])

            run_reactive!(notebook, notebook.cells[15])
            @test notebook.cells[15].output_repr == "\"4-2-3-5\""
        end
        
        @testset "Errors" begin
            run_reactive!(notebook, notebook.cells[6:9])

            # should all err, no change to `x`
            run_reactive!(notebook, notebook.cells[15])
            @test notebook.cells[15].output_repr == "\"4-2-3-5\""
        end

        @testset "Maintain order when possible" begin
            run_reactive!(notebook, notebook.cells[10:14])

            run_reactive!(notebook, notebook.cells[15])
            @test notebook.cells[15].output_repr == "\"4-2-3-5-10-11-12-13-14\""
        end
        

        run_reactive!(notebook, notebook.cells[16:18])
        @test notebook.cells[16].error_repr == nothing
        @test notebook.cells[16].output_repr == "34"
        @test notebook.cells[17].error_repr == nothing
        @test notebook.cells[18].error_repr == nothing

        notebook.cells[18].code = "υ = 8"
        run_reactive!(notebook, notebook.cells[18])
        @test notebook.cells[16].output_repr == "24"
        
        run_reactive!(notebook, notebook.cells[19:22])
        @test notebook.cells[19].error_repr == nothing
        @test notebook.cells[19].output_repr == "60"
        @test notebook.cells[20].error_repr == nothing
        @test notebook.cells[21].error_repr == nothing
        @test notebook.cells[22].error_repr == nothing

        notebook.cells[22].code = "y = 0"
        run_reactive!(notebook, notebook.cells[22])
        @test notebook.cells[19].output_repr == "38"

        WorkspaceManager.unmake_workspace(notebook)
    end
end

Pluto.set_ENV_defaults()
