# using LibGit2
import Pkg
using Test
using Pluto.Configuration: CompilerOptions
using Pluto.WorkspaceManager: _merge_notebook_compiler_options
import Pluto: update_save_run!, update_run!, WorkspaceManager, ClientSession, ServerSession, Notebook, Cell, project_relative_path, SessionActions, load_notebook
import Distributed

const pluto_test_registry_spec = Pkg.RegistrySpec(;
    url="https://github.com/JuliaPluto/PlutoPkgTestRegistry", 
    uuid=Base.UUID("96d04d5f-8721-475f-89c4-5ee455d3eda0"),
    name="PlutoPkgTestRegistry",
)

@testset "Built-in Pkg" begin
    
    # Pkg.Registry.rm("General")
    Pkg.Registry.add(pluto_test_registry_spec)


    @testset "Basic" begin
        fakeclient = ClientSession(:fake, nothing)
        🍭 = ServerSession()
        🍭.connected_clients[fakeclient.id] = fakeclient

        notebook = Notebook([
            Cell("import PlutoPkgTestA"), # cell 1
            Cell("PlutoPkgTestA.MY_VERSION |> Text"),
            Cell("import PlutoPkgTestB"), # cell 3
            Cell("PlutoPkgTestB.MY_VERSION |> Text"),
            Cell("import PlutoPkgTestC"), # cell 5
            Cell("PlutoPkgTestC.MY_VERSION |> Text"),
            Cell("import PlutoPkgTestD"), # cell 7
            Cell("PlutoPkgTestD.MY_VERSION |> Text"),
            Cell("eval(:(import DataFrames))")
        ])
        fakeclient.connected_notebook = notebook

        update_save_run!(🍭, notebook, notebook.cells[[1, 2, 7, 8]])
        @test notebook.cells[1].errored == false
        @test notebook.cells[2].errored == false
        @test notebook.cells[7].errored == false
        @test notebook.cells[8].errored == false

        @test notebook.nbpkg_ctx !== nothing
        @test notebook.nbpkg_restart_recommended_msg === nothing
        @test notebook.nbpkg_restart_required_msg === nothing

        terminals = notebook.nbpkg_terminal_outputs

        @test haskey(terminals, "PlutoPkgTestA")
        @test haskey(terminals, "PlutoPkgTestD")
        @test terminals["PlutoPkgTestA"] == terminals["PlutoPkgTestD"]


        @test notebook.cells[2].output.body == "0.3.1"
        @test notebook.cells[8].output.body == "0.1.0"


        old_A_terminal = terminals["PlutoPkgTestA"]

        update_save_run!(🍭, notebook, notebook.cells[[3, 4]])

        @test notebook.cells[3].errored == false
        @test notebook.cells[4].errored == false

        @test notebook.nbpkg_ctx !== nothing
        @test notebook.nbpkg_restart_recommended_msg === nothing
        @test notebook.nbpkg_restart_required_msg === nothing

        @test haskey(terminals, "PlutoPkgTestB")
        @test terminals["PlutoPkgTestA"] == terminals["PlutoPkgTestD"] == old_A_terminal

        @test terminals["PlutoPkgTestA"] != terminals["PlutoPkgTestB"]


        @test notebook.cells[4].output.body == "1.0.0"

        update_save_run!(🍭, notebook, notebook.cells[[5, 6]])

        @test notebook.cells[5].errored == false
        @test notebook.cells[6].errored == false
        
        @test notebook.nbpkg_ctx !== nothing
        @test (
            notebook.nbpkg_restart_recommended_msg !==  nothing || notebook.nbpkg_restart_required_msg !== nothing
        )
        @test notebook.nbpkg_restart_required_msg !== nothing

        # running cells again should persist the message

        update_save_run!(🍭, notebook, notebook.cells[1:8])
        @test notebook.nbpkg_restart_required_msg !== nothing


        # restart the process, this should match the function `response_restrart_process`, except not async

        Pluto.response_restrart_process(Pluto.ClientRequest(
            session=🍭,
            notebook=notebook,
        ); run_async=false)

        # @test_nowarn SessionActions.shutdown(🍭, notebook; keep_in_session=true, async=true)
        # @test_nowarn update_save_run!(🍭, notebook, notebook.cells[1:8]; , save=true)

        @test notebook.cells[1].errored == false
        @test notebook.cells[2].errored == false
        @test notebook.cells[3].errored == false
        @test notebook.cells[4].errored == false
        @test notebook.cells[5].errored == false
        @test notebook.cells[6].errored == false
        @test notebook.cells[7].errored == false
        @test notebook.cells[8].errored == false

        @test notebook.nbpkg_ctx !== nothing
        @test notebook.nbpkg_restart_recommended_msg === nothing
        @test notebook.nbpkg_restart_required_msg === nothing


        @test notebook.cells[2].output.body == "0.2.2"
        @test notebook.cells[4].output.body == "1.0.0"
        @test notebook.cells[6].output.body == "1.0.0"
        @test notebook.cells[8].output.body == "0.1.0"




        # we should have an isolated environment, so importing DataFrames should not work, even though it is available in the parent process.
        update_save_run!(🍭, notebook, notebook.cells[9])
        @test notebook.cells[9].errored == true


        WorkspaceManager.unmake_workspace((🍭, notebook))
    end

    pre_pkg_notebook = """
    ### A Pluto.jl notebook ###
    # v0.14.7

    using Markdown
    using InteractiveUtils

    # ╔═╡ 22364cc8-c792-11eb-3458-75afd80f5a03
    using Example

    # ╔═╡ ca0765b8-ce3f-4869-bd65-855905d49a2d
    using Dates

    # ╔═╡ 5cbe4ac1-1bc5-4ef1-95ce-e09749343088
    domath(20)

    # ╔═╡ Cell order:
    # ╠═22364cc8-c792-11eb-3458-75afd80f5a03
    # ╠═ca0765b8-ce3f-4869-bd65-855905d49a2d
    # ╠═5cbe4ac1-1bc5-4ef1-95ce-e09749343088
    """

    local post_pkg_notebook = nothing

    @testset "Backwards compat" begin
        fakeclient = ClientSession(:fake, nothing)
        🍭 = ServerSession()
        🍭.connected_clients[fakeclient.id] = fakeclient

        dir = mktempdir()
        path = joinpath(dir, "hello.jl")
        write(path, pre_pkg_notebook)

        @test num_backups_in(dir) == 0

        notebook = SessionActions.open(🍭, path; run_async=false)
        fakeclient.connected_notebook = notebook
        
        @test num_backups_in(dir) == 0
        # @test num_backups_in(dir) == 1

        post_pkg_notebook = read(path, String)

        # test that pkg cells got added
        @test length(post_pkg_notebook) > length(pre_pkg_notebook) + 50

        @test notebook.nbpkg_ctx !== nothing
        @test notebook.nbpkg_restart_recommended_msg === nothing
        @test notebook.nbpkg_restart_required_msg === nothing
    end

    @testset "Forwards compat" begin
        # Using Distributed, we will create a new Julia process in which we install Pluto 0.14.7 (before PlutoPkg). We run the new notebook file on the old Pluto.
        p = Distributed.addprocs(1) |> first

        @test post_pkg_notebook isa String

        Distributed.remotecall_eval(Main, p, quote
            path = tempname()
            write(path, $(post_pkg_notebook))
            import Pkg
            # optimization:
            if isdefined(Pkg, :UPDATED_REGISTRY_THIS_SESSION)
                Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true
            end

            Pkg.activate(mktempdir())
            Pkg.add(Pkg.PackageSpec(;name="Pluto",version=v"0.14.7"))
            import Pluto
            @assert Pluto.PLUTO_VERSION == v"0.14.7"

            s = Pluto.ServerSession()
            s.options.evaluation.workspace_use_distributed = false

            nb = Pluto.SessionActions.open(s, path; run_async=false)

            nothing
        end)

        # Cells that use Example will error because the package is not installed.

        # @test Distributed.remotecall_eval(Main, p, quote
        #     nb.cells[1].errored == false
        # end)
        @test Distributed.remotecall_eval(Main, p, quote
            nb.cells[2].errored == false
        end)
        # @test Distributed.remotecall_eval(Main, p, quote
        #     nb.cells[3].errored == false
        # end)
        # @test Distributed.remotecall_eval(Main, p, quote
        #     nb.cells[3].output.body == "25"
        # end)

        Distributed.rmprocs([p])
    end

    # @test false

    # @testset "File format" begin
    #     notebook = Notebook([
    #         Cell("import PlutoPkgTestA"), # cell 1
    #         Cell("PlutoPkgTestA.MY_VERSION |> Text"),
    #         Cell("import PlutoPkgTestB"), # cell 3
    #         Cell("PlutoPkgTestB.MY_VERSION |> Text"),
    #         Cell("import PlutoPkgTestC"), # cell 5
    #         Cell("PlutoPkgTestC.MY_VERSION |> Text"),
    #         Cell("import PlutoPkgTestD"), # cell 7
    #         Cell("PlutoPkgTestD.MY_VERSION |> Text"),
    #         Cell("import PlutoPkgTestE"), # cell 9
    #         Cell("PlutoPkgTestE.MY_VERSION |> Text"),
    #         Cell("eval(:(import DataFrames))")
    #     ])

    #     file1 = tempname()
    #     notebook.path = file1

    #     save_notebook()


    #     save_notebook
    # end


    Pkg.Registry.rm(pluto_test_registry_spec)
    # Pkg.Registry.add("General")
end

# reg_path = mktempdir()
# repo = LibGit2.clone("https://github.com/JuliaRegistries/General.git", reg_path)

# LibGit2.checkout!(repo, "aef26d37e1d0e8f8387c011ccb7c4a38398a18f6")


