# will be executed on workspace process

using Markdown
import Markdown: html, htmlinline, LaTeX, withtag, htmlesc
import Distributed

# We add a method for the Markdown -> HTML conversion that takes a LaTeX chunk from the Markdown tree and adds our custom span
function htmlinline(io::IO, x::LaTeX)
    withtag(io, :span, :class => "tex") do
        print(io, '$')
        htmlesc(io, x.formula)
        print(io, '$')
    end
end

# this one for block equations: (double $$)
function html(io::IO, x::LaTeX)
    withtag(io, :p, :class => "tex") do
        print(io, '$', '$')
        htmlesc(io, x.formula)
        print(io, '$', '$')
    end
end

"The `IOContext` used for converting arbitrary objects to pretty strings."
iocontext = IOContext(stdout, :color => false, :compact => true, :limit => true, :displaysize => (18, 120))

"""Format `val` using the richest possible output, return formatted string and used MIME type.

Currently, the MIME type is one of `text/html` or `text/plain`, the former being richest."""
function format_output(val::Any)::Tuple{String, MIME}
    # in order of coolness
    # text/plain always matches
    mime = let
        mimes = [MIME("text/html"), MIME("text/plain")]
        first(filter(m->Base.invokelatest(showable, m, val), mimes))
    end
    
    if val === nothing
        "", mime
    else
        try
            Base.invokelatest(repr, mime, val; context = iocontext), mime
        catch ex
            Base.invokelatest(repr, mime, ex; context = iocontext), mime
        end
    end
end

function format_output(ex::Exception, bt::Array{Any, 1})::Tuple{String, MIME}
    sprint(showerror, ex, bt), MIME("text/plain")
end

function format_output(ex::Exception)::Tuple{String, MIME}
    sprint(showerror, ex), MIME("text/plain")
end

function format_output(val::CapturedException)::Tuple{String, MIME}

    ## We hide the part of the stacktrace that belongs to Pluto's evalling of user code.

    bt = try
        new_bt = val.processed_bt
        # If this is a ModuleWorkspace, then that's everything starting from the last `eval`.
        # For a ProcessWorkspace, it's everything starting from the 2nd to last `eval`.
        howdeep = Distributed.myid() == 1 ? 1 : 2

        for _ in 1:howdeep
            until = findfirst(b -> b[1].func == :eval, reverse(new_bt))
            new_bt = until === nothing ? new_bt : new_bt[1:(length(new_bt) - until)]
        end

        # We don't include the deepest item of the stacktrace, since it is always
        # `top-level scope at none:0`
        new_bt[1:end-1]
    catch ex
        val.processed_bt
    end

    format_output(val.ex, bt)
end