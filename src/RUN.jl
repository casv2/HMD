module RUN

using IPFitting
using JuLIP
using ASE
using HMD
using LinearAlgebra
using Plots

function do_fit(B, Vref, al, weights, α, β, ncoms; calc_err=true)
    dB = IPFitting.Lsq.LsqDB("", B, al);

    Ψ, Y = IPFitting.Lsq.get_lsq_system(dB, verbose=true,
                                Vref=Vref, Ibasis = :,Itrain = :,
                                weights=weights, regularisers = [])
    
    c_samples = HMD.BRR.do_brr(Ψ, Y, α, β, ncoms);
    
    IP = JuLIP.MLIPs.SumIP(Vref, JuLIP.MLIPs.combine(B, c_samples[:,1]))

    if calc_err 
        add_fits_serial!(IP, al, fitkey="IP")
        rmse_, rmserel_ = rmse(al; fitkey="IP");
        rmse_table(rmse_, rmserel_)
    end
    
    return IP, c_samples
end

function run_HMD(B, Vref, weights, al, start_configs, run_info, α=100.0, β=0.1, ncoms=5)#, nsteps=10000)
    for (j,start_config) in enumerate(start_configs)
        config_type = configtype(start_config)
        for l in 1:convert(Int,run_info["HMD_iters"])
            m = (j-1)*run_info["HMD_iters"] + l
            IP, c_samples = do_fit(B, Vref, al, weights, α, β, ncoms)
            E_tot, E_pot, E_kin, T, P, varEs, varFs, cfgs = run(IP, B, Vref, c_samples, 
                    start_config.at, nsteps=run_info["nsteps"], temp=run_info[config_type]["temp"], 
                    dt=run_info[config_type]["dt"], τ=run_info[config_type]["τ"])
            
            plot_HMD(E_tot, E_pot, E_kin, T, P, m, k=1)
            
            write_xyz("./crash_$(m).xyz", ASEAtoms(cfgs[end]))
            at = HMD.CALC.CASTEP_calculator(cfgs[end])
            al = vcat(al, at)

            #write_xyz("./HMD_surf_vac/crash_$(m).xyz", cfgs[end])
            #run(`/Users/Cas/anaconda2/bin/python /Users/Cas/.julia/dev/MDLearn/HMD_surf_vac/convert.py $(m) $(config_type)`)
        end
    end
    return al
end

function run(IP, B, Vref, c_samples, at; nsteps=100, temp=100, dt=1.0, τ=0.5)
    E_tot = zeros(nsteps)
    E_pot = zeros(nsteps)
    E_kin = zeros(nsteps)
    T = zeros(nsteps)
    P = zeros(nsteps)
    varEs = zeros(nsteps)
    varFs = zeros(nsteps)

    E0 = energy(IP, at)

    at = HMD.MD.MaxwellBoltzmann_scale(at, temp)
    at = HMD.MD.Stationary(at)

    cfgs = []

    running = true

    i = 2
    while running && i < nsteps
        at, p = HMD.COM.VelocityVerlet_com(Vref, B, c_samples, at, dt * HMD.MD.fs, τ=τ)
        P[i] = p
        Ek = ((0.5 * sum(at.M) * norm(at.P ./ at.M)^2)/length(at.M)) / length(at.M)
        Ep = (energy(IP, at) - E0) / length(at.M)
        E_tot[i] = Ek + Ep
        E_pot[i] = Ep
        E_kin[i] = Ek
        T[i] = Ek / (1.5 * HMD.MD.kB)
        i+=1
        if i % 10 == 0
            @show p, abs((E_tot[i-1]/E_tot[2] - 1.0))
            if abs((E_tot[i-1]/E_tot[2] - 1.0)) > 0.02
                running = false
            end
            τ *= 1.05
            push!(cfgs, at)
        end
    end
    
    return E_tot[1:i], E_pot[1:i], E_kin[1:i], T[1:i], P[1:i], varEs[1:i], varFs[1:i], cfgs
end

function plot_HMD(E_tot, E_pot, E_kin, T, P, i; k=50) # varEs,
    p1 = plot()
    plot!(p1,E_tot[2:end-k], label="")
    plot!(p1,E_kin[2:end-k], label="")
    plot!(p1,E_pot[2:end-k], label="")
    ylabel!(p1, "Energy (eV)")
    p2 = plot()
    plot!(p2, T[2:end-k],label="")
    ylabel!(p2, "T (K)")
    p4 = plot()
    plot!(p4, P[2:end-k],label="")
    xlabel!(p4,"MDstep")
    ylabel!(p4, "P")
    p5 = plot(p1, p2, p4, size=(400,550), layout=grid(3, 1, heights=[0.6, 0.2, 0.2]))
    savefig("./HMD_$(i).pdf")
end


end