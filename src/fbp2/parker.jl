# fbp2/parker.jl
# Parker weighting for FBP reconstruction http://doi.org/10.1118/1.595078

export parker_weight
# using Sinograms: SinoGeom, SinoPar, SinoFan, SinoMoj
using LazyGrids: ndgrid


# parallel-beam case: returns a Vector
function parker_weight_par(
    orbit::RealU,
    ad::AbstractVector{<:RealU}, # angles in degrees: sg.ad - sg.orbit_start
    ;
    T::Type{<:Real} = Float32,
)

    wt = ones(T, length(ad))

    if (orbit ÷ 180) * 180 == orbit
        return wt # no weighting needed
    end

    if orbit < 180
        @warn("orbit $orbit < 180")
        return wt # nonuniform weighting would not help
    end

    orbit > 360 && error("only 180 ≤ |orbit| ≤ 360 supported for Parker weighting")
    extra = orbit - 180 # extra beyond 180

    ad = abs.(ad)
    ii = ad .< extra
    @. wt[ii] = abs2(sin(ad[ii] / extra * π/2))
    ii = ad .≥ 180
    @. wt[ii] = abs2(sin((orbit - ad[ii]) / extra * π/2))
    wt .*= orbit / 180 # because of the back-projector normalization
    return wt
end


"""
    parker_weight(sg::SinoGeom ; T = Float32)
Compute Parker weighting for non-360° orbits.
Returns `Vector{T}` of length `sg.na` for `SinoPar`.
Returns `Matrix{T}` of size `dims(sg)` for `SinoFan`.
"""
parker_weight(sg::SinoPar ; T::Type{<:Real} = Float32)::Vector{T} =
    parker_weight_par(sg.orbit, sg.ad .- sg.orbit_start ; T)


function parker_weight_fan(
    nb::Int,
    na::Int,
    orbit::RealU,
    orbit_short::RealU,
    ar::AbstractVector{<:RealU}, # angles in radians
    gam::AbstractVector{<:RealU},
    gamma_max::RealU, # half of fan angle
    ;
    T::Type{<:Real} = Float32,
)

    na == length(ar) || error("na bug")
    orbit < orbit_short - eps() &&
        @warn("orbit $orbit is less than a short scan $orbit_short")

    orbit > orbit_short + rad2deg(ar[2] - ar[1]) &&
        @warn("orbit $orbit exeeds short scan $orbit_short by %g views")
    #   (orbit - orbit_short) / rad2deg(ar[2] - ar[1]))

    bet = ar .- ar[1] # trick: force 0 start, so this ignores orbit_start!
    (gg, bb) = ndgrid(gam, bet)

    fun = (x) -> sin(π/2 * x)^2 # smooth out [0,1] ramp
    #=
    todo: We could use integrals of this function
    over the tiny angular range of each projection view,
    so that the sum over beta of these functions is a constant.
    =#

    wt = zeros(T,nb,na) # any extra views will get 0 weight
    ii = @. bb < 2 * (gamma_max .- gg) # 0 <= bb not needed
    tmp = bb[ii] ./ (2 * (gamma_max .- gg[ii]))
    @. wt[ii] = fun(tmp)

    ii = @. (2 * (gamma_max - gg) ≤ bb) & (bb < π - 2 * gg)
    wt[ii] .= 1

    ii = @. (π - 2 * gg < bb) & (bb ≤ π + 2 * gamma_max)
    tmp = @. (π + 2*gamma_max - bb[ii]) / (2 * (gamma_max + gg[ii]))
    @. wt[ii] = fun(tmp)

    wt .*= orbit / 180 # because of the back-projector normalization
    return wt
end


function parker_weight(sg::SinoFan; T::Type{<:Real} = Float32)::Matrix{T}
    wt = ones(T, dims(sg))
    if (sg.orbit ÷ 360) * 360 == sg.orbit
        return wt
    end
    return parker_weight_fan(
        sg.nb, sg.na, sg.orbit, sg.orbit_short,
        sg.ar, sg.gamma, sg.gamma_max; T
    )
end


function parker_weight(sg::SinoMoj ; T::Type{<:Real} = Float32)::Vector{T}
    orbit = abs(sg.orbit)
    na = sg.na
    ((sg.orbit ÷ 180) * 180 == orbit) ||
        throw("No Parker weighting for Mojette geometry with orbit=$orbit")
    wt = ones(T, na)
    return wt
end
