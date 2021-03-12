# # Shallow Water Example: an unstable Bickley jet 
#
# This example shows how to use `Oceananigans.ShallowWaterModel` to simulate
# the evolution of an unstable, geostrophically balanced, Bickley jet.
# The model solves the governing equations for the shallow water model in
# conservation form.  The geometry is that of a periodic channel
# in the ``x``-direction with a flat bottom and a free-surface.  The initial
# conditions are that of a Bickley jet with small amplitude perturbations.
# The interested reader can see ["The nonlinear evolution of barotropically unstable jets," J. Phys. Oceanogr. (2003)](https://doi.org/10.1175/1520-0485(2003)033<2173:TNEOBU>2.0.CO;2)
# for more details on this specific problem. 
#
# Unlike the other models, the fields that are simulated are the mass transports, 
# ``uh`` and ``vh`` in the ``x`` and ``y`` directions, respectively,
# and the height ``h``.  Note that ``u`` and ``v`` are the velocities, which 
# can easily be computed when needed.
#
# ## Install dependencies
#
# First we make sure that we have all of the packages that are required to
# run the simulation.
# ```julia
# using Pkg
# pkg"add Oceananigans, NCDatasets, Plots, Printf, Polynomials"
# ```
#

using Oceananigans
using Oceananigans.Models: ShallowWaterModel

# ## Two-dimensional domain 
#
# The shallow water model is a two-dimensional model and we must specify
# the number of vertical grid points to be one.  
# We pick the length of the domain to fit one unstable mode along the channel
# exactly.  Note that ``Lz`` is the mean depth of the fluid.  It is determined
# using linear stability theory that the zonal wavenumber that yields the most unstable
# mode that fits in this zonal channel has a growth rate of ``\sigma \approx 0.14``.

Lx = 2π
Ly = 20
Lz = 1
Nx = 128
Ny = Nx

grid = RegularRectilinearGrid(size = (Nx, Ny, 1),
                            x = (0, Lx), y = (0, Ly), z = (0, Lz),
                            topology = (Periodic, Bounded, Bounded))

# ## Physical parameters
#
# This is a toy problem and we choose the parameters so this jet idealizes
# a relatively narrow mesoscale jet.   
# The physical parameters are
#
#   * ``f``: Coriolis parameter
#   * ``g``: Acceleration due to gravity
#   * ``U``: Maximum jet speed
#   * ``\Delta\eta``: Maximum free-surface deformation that is dictated by geostrophy
#   * ``\epsilon`` : Amplitude of the perturbation

f = 1
g = 9.80665
U = 1.0
Δη = f * U / g
ϵ = 1e-4
nothing # hide

# ## Building a `ShallowWaterModel`
#
# We use `grid`, `coriolis` and `gravitational_acceleration` to build the model.
# Furthermore, we specify `RungeKutta3` for time-stepping and `WENO5` for advection.

model = ShallowWaterModel(
    timestepper=:RungeKutta3,
    advection=WENO5(),
    grid=grid,
    gravitational_acceleration=g,
    coriolis=FPlane(f=f),
    )

# ## Background state and perturbation
# 
# We specify `Ω` to be the background vorticity of the jet in the absence of any perturbations.
# The initial conditions include a small-ampitude perturbation that decays away from the center
# of the jet.

  Ω(x, y, z) = 2 * U * sech(y - Ly/2)^2 * tanh(y - Ly/2)
 uⁱ(x, y, z) =   U * sech(y - Ly/2)^2 + ϵ * exp(- (y - Ly/2)^2 ) * randn()
 ηⁱ(x, y, z) = -Δη * tanh(y - Ly/2)
 hⁱ(x, y, z) = model.grid.Lz + ηⁱ(x, y, z)
uhⁱ(x, y, z) = uⁱ(x, y, z) * hⁱ(x, y, z)
nothing # hide

# We set the initial conditions for the zonal mass transport `uhⁱ` and height `hⁱ`.

set!(model, uh = uhⁱ , h = hⁱ)

# We compute the total vorticity and the perturbation vorticity.

uh, vh, h = model.solution
        u = ComputedField(uh / h)
        v = ComputedField(vh / h)
  ω_field = ComputedField( ∂x(vh/h) - ∂y(uh/h) )
   ω_pert = ComputedField( ω_field - Ω )

# ## Running a `Simulation`
#
# We pick the time-step that ensures to resolve the surface gravity waves.
# A time-step wizard can be applied to use an adaptive time step.

simulation = Simulation(model, Δt = 1e-2, stop_time = 150.00)

# ## Prepare output files
#
# Define a function to compute the norm of the perturbation on the cross channel velocity.
# We obtain the `norm` function from `LinearAlgebra`.

using LinearAlgebra, Printf

function perturbation_norm(model)
    compute!(v)
    return norm(interior(v))
end
nothing # hide

# Choose the two fields to be output to be the total and perturbation vorticity.

outputs = (ω_total = ω_field, ω_pert = ω_pert)

# Build the `output_writer` for the two-dimensional fields to be output.
# Output every `t = 1.0`.

simulation.output_writers[:fields] =
    NetCDFOutputWriter(
        model,
        (ω = ω_field, ωp = ω_pert),
        filepath=joinpath(@__DIR__, "Bickley_jet_shallow_water.nc"),
        schedule=TimeInterval(1.0),
        mode = "c")

# Build the `output_writer` for the growth rate, which is a scalar field.
# Output every time step.
#

simulation.output_writers[:growth] =
    NetCDFOutputWriter(
        model,
        (perturbation_norm = perturbation_norm,),
        filepath=joinpath(@__DIR__, "perturbation_norm_shallow_water.nc"),
        schedule=IterationInterval(1),
        dimensions=(perturbation_norm=(),),
        mode = "c")

run!(simulation)

# ## Visualize the results
#

using NCDatasets
nothing # hide

# This sets the environment to avoid an error in GKSwstype

ENV["GKSwstype"] = "100"

# Define the coordinates for plotting

xf = xnodes(ω_field)
yf = ynodes(ω_field)
nothing # hide

# Define keyword arguments for plotting the contours

kwargs = (
         xlabel = "x",
         ylabel = "y",
           fill = true,
         levels = 20,
      linewidth = 0,
          color = :balance,
       colorbar = true,
           ylim = (0, Ly),
           xlim = (0, Lx)
)
nothing # hide

# Read in the `output_writer` for the two-dimensional fields
# and then create an animation showing both the total and perturbation
# vorticities.

using Plots

ds = NCDataset(simulation.output_writers[:fields].filepath, "r")

iterations = keys(ds["time"])

anim = @animate for (iter, t) in enumerate(ds["time"])
     ω = ds["ω"][:, :, 1, iter]
    ωp = ds["ωp"][:, :, 1, iter]

     ω_max = maximum(abs, ω)
    ωp_max = maximum(abs, ωp)

     plot_ω = contour(xf, yf, ω',  clim=(-ω_max,  ω_max),  title=@sprintf("Total ω at t = %.3f", t); kwargs...)
    plot_ωp = contour(xf, yf, ωp', clim=(-ωp_max, ωp_max), title=@sprintf("Perturbation ω at t = %.3f", t); kwargs...)

    plot(plot_ω, plot_ωp, layout = (1,2), size=(1200, 500))

    print("At t = ", t, " maximum of ωp = ", maximum(abs, ωp), "\n")
end

close(ds)

mp4(anim, "Bickley_Jet_ShallowWater.mp4", fps=15)

# Read in the `output_writer` for the scalar field.

ds2 = NCDataset(simulation.output_writers[:growth].filepath, "r")

iterations = keys(ds2["time"])

t = ds2["time"][:]
σ = ds2["perturbation_norm"][:]

close(ds2)

# Import `Polynomials` to be able to use `best_fit`.
# Compute the best fit slope and save the figure.

using Polynomials

I = 6000:7000
best_fit = fit((t[I]), log.(σ[I]), 1)
poly = 2 .* exp.(best_fit[0] .+ best_fit[1]*t[I])

plt = plot(t[1000:end], log.(σ[1000:end]), lw=4, label="sigma", 
        xlabel="time", ylabel="log(v)", title="growth of perturbation", legend=:bottomright)
plot!(plt, t[I], log.(poly), lw=4, label="best fit")

# We can compute the slope of the curve on a log scale, which approximates the growth rate
# of the simulation. This should be close to the theoretical prediction.

print("Growth rate in the simulation is approximated to be ", best_fit[1], 
      ", which is close to the theoretical value of 0.14.")