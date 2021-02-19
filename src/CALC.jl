module CALC

using PyCall
using ASE
using IPFitting: Dat
using IPFitting
using LinearAlgebra
EAM = pyimport("ase.calculators.eam")["EAM"]
CASTEP = pyimport("ase.calculators.castep")["Castep"]
DFTB = pyimport("ase.calculators.dftb")["Dftb"]

function EAM_calculator(at, config_type)
    py_at = ASEAtoms(at)

    calculator = EAM(potential=@__DIR__() * "/Ti1.eam.fs")
    py_at.po[:set_calculator](calculator)

    E = py_at.po.get_potential_energy()
    F = py_at.po.get_forces()
    #V = -1.0 * py_at.get_stress() * py_at.get_volume()

    D_info = PyDict(py_at.po[:info])
    D_arrays = PyDict(py_at.po[:arrays])

    D_info["config_type"] = "HMD_" * config_type
    D_info["energy"] = E
    D_arrays["force"] = F

    py_at.po[:info] = D_info
    py_at.po[:arrays] = D_arrays

    dat = Dat( at,"HMD", E = E, F = F)#, V = V)

    return dat, py_at
end

function NRLTB_calculator(at, config_type, m)
    py_at = ASEAtoms(at)

    write_xyz("crash_$(m).xyz", py_at)
    run(`/Users/Cas/anaconda2/bin/python /Users/Cas/.julia/dev/HMD/convert.py $(m)`)
    #V = -1.0 * py_at.get_stress() * py_at.get_volume()

    al = IPFitting.Data.read_xyz("/Users/Cas/.julia/dev/HMD/crash_conv_$(m).xyz", energy_key="energy", force_key="forces")
    E = al[1].D["E"]
    F = al[1].D["F"]

    dat = Dat( at,"HMD_" * config_type, E = E, F = F)#, V = V)

    return dat, py_at
end

function CASTEP_calculator(at, config_type, dft_settings)
    py_at = ASEAtoms(at)

    calculator = CASTEP()
    calculator[:_castep_command] = dft_settings["_castep_command"]
    calculator[:_directory] = dft_settings["_directory"]
    calculator.param[:cut_off_energy] = dft_settings["cut_off_energy"]
    calculator.param[:calculate_stress] = dft_settings["calculate_stress"]
    calculator.param[:smearing_width] = dft_settings["smearing_width"]
    calculator.param[:finite_basis_corr] = dft_settings["finite_basis_corr"]
    calculator.param[:mixing_scheme] = dft_settings["mixing_scheme"]
    calculator.param[:write_checkpoint] = dft_settings["write_checkpoint"]
    #calculator.cell[:kpoints_mp_spacing] = 0.1
    calculator.cell[:kpoint_mp_spacing] = dft_settings["kpoint_mp_spacing"]
    calculator.param[:fine_grid_scale] = dft_settings["fine_grid_scale"]
    py_at.po[:set_calculator](calculator)

    E = py_at.po.get_potential_energy(force_consistent=true)
    F = py_at.po.get_forces()
    V = -1.0 * py_at.po.get_stress(voigt=false) * py_at.po.get_volume()

    dat = Dat( at, "HMD_" * config_type, E = E, F = F, V = V)

    D_info = PyDict(py_at.po[:info])
    D_arrays = PyDict(py_at.po[:arrays])

    D_info["config_type"] = "HMD_" * config_type
    D_info["energy"] = E
    D_info["virial"] = V
    D_arrays["force"] = F

    py_at.po[:info] = D_info
    py_at.po[:arrays] = D_arrays

    return dat, py_at
end

function DFTB_calculator(at, config_type, dftb_settings)
    py_at = ASEAtoms(at)

    PyCall.PyDict(PyCall.pyimport("os").environ)["ASE_DFTB_COMMAND"] = dftb_settings["ASE_DFTB_COMMAND"]
    PyCall.PyDict(PyCall.pyimport("os").environ)["DFTB_PREFIX"] = dftb_settings["DFTB_PREFIX"]

    kpoint_spacing = dftb_settings["kpoint_spacing"]

    kspace = norm.(eachrow(at.cell)) .^ -1
    kpoints = vcat(floor.(Int, kspace ./ kpoint_spacing)...)

    @show kpoints

    calculator = DFTB(at=py_at.po,
                    label="Ti",
                    kpts=kpoints,
                    Hamiltonian_="DFTB",
                    Hamiltonian_SCC="Yes",
                    Hamiltonian_SCCTolerance=1e-8,
                    Hamiltonian_Filling_="Fermi",
                    Hamiltonian_Filling_Temperature=300)
    
    py_at.po[:set_calculator](calculator)

    E = py_at.po.get_potential_energy()
    F = py_at.po.get_forces()
    #V = -1.0 * py_at.po.get_stress(voigt=false) * py_at.po.get_volume()

    dat = Dat( at, "HMD_" * config_type, E = E, F = F)#, V = V)

    D_info = PyDict(py_at.po[:info])
    D_arrays = PyDict(py_at.po[:arrays])

    D_info["config_type"] = "HMD_" * config_type
    D_info["energy"] = E
    #D_info["virial"] = V
    D_arrays["force"] = F

    @show D_info
    @show D_arrays

    @show E
    #@show V
    @show F

    py_at.po[:info] = D_info
    py_at.po[:arrays] = D_arrays

    return dat, py_at
end

end
