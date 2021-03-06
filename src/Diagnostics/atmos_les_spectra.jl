# Spectrum calculator for AtmosLES

struct AtmosLESSpectraDiagnosticsParams <: DiagnosticsGroupParams
    nor::Float64
end

"""
    setup_atmos_spectra_diagnostics(
        ::AtmosLESConfigType,
        interval::String,
        out_prefix::String;
        writer = NetCDFWriter(),
        interpol = nothing,
        nor = Inf,
    )

Create the "AtmosLESSpectra" `DiagnosticsGroup` which contains the following
diagnostic variable:

- spectrum: power spectrum from 3D velocity fields

This variable is output with the `k` dimension (wave number) on an interpolated
grid (`interpol` _must_ be specified) as well as a (unlimited) `time` dimension
at the specified `interval`.
"""
function setup_atmos_spectra_diagnostics(
    ::AtmosLESConfigType,
    interval::String,
    out_prefix::String,
    nor::Float64;
    writer = NetCDFWriter(),
    interpol = nothing,
)
    @assert !isnothing(interpol)

    return DiagnosticsGroup(
        "AtmosLESSpectra",
        Diagnostics.atmos_les_spectra_init,
        Diagnostics.atmos_les_spectra_fini,
        Diagnostics.atmos_les_spectra_collect,
        interval,
        out_prefix,
        writer,
        interpol,
        AtmosLESSpectraDiagnosticsParams(nor),
    )
end

function get_spectrum(mpicomm, mpirank, Q, bl, interpol, nor)
    FT = eltype(Q)
    istate = similar(Q.data, interpol.Npl, number_states(bl, Prognostic(), FT))
    interpolate_local!(interpol, Q.data, istate)
    all_state_data = accumulate_interpolated_data(mpicomm, interpol, istate)
    if mpirank == 0
        u = all_state_data[:, :, :, 2] ./ all_state_data[:, :, :, 1]
        v = all_state_data[:, :, :, 3] ./ all_state_data[:, :, :, 1]
        w = all_state_data[:, :, :, 4] ./ all_state_data[:, :, :, 1]
        x1 = Array(interpol.x1g)
        d = length(x1)
        s, k = power_spectrum_3d(
            AtmosLESConfigType(),
            u,
            v,
            w,
            x1[d] - x1[1],
            d,
            nor,
        )
        return s, k
    end
    return nothing, nothing
end

function atmos_les_spectra_init(dgngrp, currtime)
    Q = Settings.Q
    bl = Settings.dg.balance_law
    mpicomm = Settings.mpicomm
    mpirank = MPI.Comm_rank(mpicomm)
    FT = eltype(Q)
    interpol = dgngrp.interpol
    nor = dgngrp.params.nor

    spectrum, wavenumber = get_spectrum(mpicomm, mpirank, Q, bl, interpol, nor)
    if mpirank == 0
        dims = OrderedDict("k" => (wavenumber, Dict()))
        vars = OrderedDict("spectrum" => (("k",), FT, Dict()))

        dprefix = @sprintf("%s_%s", dgngrp.out_prefix, dgngrp.name)
        dfilename = joinpath(Settings.output_dir, dprefix)
        noov = Settings.no_overwrite
        init_data(dgngrp.writer, dfilename, noov, dims, vars)
    end

    return nothing
end

function atmos_les_spectra_collect(dgngrp, currtime)
    Q = Settings.Q
    bl = Settings.dg.balance_law
    mpicomm = Settings.mpicomm
    mpirank = MPI.Comm_rank(mpicomm)
    FT = eltype(Q)
    interpol = dgngrp.interpol
    nor = dgngrp.params.nor

    spectrum, _ = get_spectrum(mpicomm, mpirank, Q, bl, interpol, nor)

    if mpirank == 0
        varvals = OrderedDict("spectrum" => spectrum)
        append_data(dgngrp.writer, varvals, currtime)
    end

    MPI.Barrier(mpicomm)
    return nothing
end

function atmos_les_spectra_fini(dgngrp, currtime) end
