##########################################################################################################
# The purpose of this file is to define commonly used and created variables used in power flow models
# This will hopefully make everything more compositional
##########################################################################################################

# extracts the start value fro,
function getstart(set, item_key, value_key, default = 0.0)
  try
    return set[item_key][value_key]
  catch
    return default
  end
end

function phase_angle_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, t[i in pm.set.bus_indexes], start = getstart(pm.set.buses, i, "t_start"))
  return t
end

function voltage_magnitude_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, pm.set.buses[i]["vmin"] <= v[i in pm.set.bus_indexes] <= pm.set.buses[i]["vmax"], start = getstart(pm.set.buses, i, "v_start", 1.0))
  return v
end

function voltage_magnitude_sqr_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, pm.set.buses[i]["vmin"]^2 <= w[i in pm.set.bus_indexes] <= pm.set.buses[i]["vmax"]^2, start = getstart(pm.set.buses, i, "w_start", 1.001))
  return w
end


function voltage_magnitude_sqr_from_on_off_variables{T}(pm::GenericPowerModel{T})
  buses = pm.set.buses
  branches = pm.set.branches

  @variable(pm.model, 0 <= w_from[i in pm.set.branch_indexes] <= buses[branches[i]["f_bus"]]["vmax"]^2, start = getstart(pm.set.buses, i, "w_from_start", 1.001))

  z = getvariable(pm.model, :line_z)
  for i in pm.set.branch_indexes
    @constraint(pm.model, w_from[i] <= z[i]*buses[branches[i]["f_bus"]]["vmax"]^2)
    @constraint(pm.model, w_from[i] >= z[i]*buses[branches[i]["f_bus"]]["vmin"]^2)
  end

  return w_from
end

function voltage_magnitude_sqr_to_on_off_variables{T}(pm::GenericPowerModel{T})
  buses = pm.set.buses
  branches = pm.set.branches

  @variable(pm.model, 0 <= w_to[i in pm.set.branch_indexes] <= buses[branches[i]["t_bus"]]["vmax"]^2, start = getstart(pm.set.buses, i, "w_to", 1.001))

  z = getvariable(pm.model, :line_z)
  for i in pm.set.branch_indexes
    @constraint(pm.model, w_to[i] <= z[i]*buses[branches[i]["t_bus"]]["vmax"]^2)
    @constraint(pm.model, w_to[i] >= z[i]*buses[branches[i]["t_bus"]]["vmin"]^2)
  end

  return w_to
end



function active_generation_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, pm.set.gens[i]["pmin"] <= pg[i in pm.set.gen_indexes] <= pm.set.gens[i]["pmax"], start = getstart(pm.set.gens, i, "pg_start"))
  return pg
end

function reactive_generation_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, pm.set.gens[i]["qmin"] <= qg[i in pm.set.gen_indexes] <= pm.set.gens[i]["qmax"], start = getstart(pm.set.gens, i, "qg_start"))
  return qg
end

function active_line_flow_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, -pm.set.branches[l]["rate_a"] <= p[(l,i,j) in pm.set.arcs] <= pm.set.branches[l]["rate_a"], start = getstart(pm.set.branches, l, "p_start"))
  return p
end

function reactive_line_flow_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, -pm.set.branches[l]["rate_a"] <= q[(l,i,j) in pm.set.arcs] <= pm.set.branches[l]["rate_a"], start = getstart(pm.set.branches, l, "q_start"))
  return q
end

function compute_voltage_product_bounds{T}(pm::GenericPowerModel{T})
  buspairs = pm.set.buspairs
  buspair_indexes = pm.set.buspair_indexes

  wr_min = [bp => -Inf for bp in buspair_indexes] 
  wr_max = [bp =>  Inf for bp in buspair_indexes] 
  wi_min = [bp => -Inf for bp in buspair_indexes]
  wi_max = [bp =>  Inf for bp in buspair_indexes] 

  for bp in buspair_indexes
    i,j = bp
    buspair = buspairs[bp]
    if buspair["angmin"] >= 0
      wr_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*cos(buspair["angmin"])
      wr_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*cos(buspair["angmax"])
      wi_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmax"])
      wi_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*sin(buspair["angmin"])
    end
    if buspair["angmax"] <= 0
      wr_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*cos(buspair["angmax"])
      wr_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*cos(buspair["angmin"])
      wi_max[bp] = buspair["v_from_min"]*buspair["v_to_min"]*sin(buspair["angmax"])
      wi_min[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmin"])
    end
    if buspair["angmin"] < 0 && buspair["angmax"] > 0
      wr_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*1.0
      wr_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*min(cos(buspair["angmin"]), cos(buspair["angmax"]))
      wi_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmax"])
      wi_min[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmin"])
    end
  end

  return wr_min, wr_max, wi_min, wi_max
end

function complex_voltage_product_variables{T}(pm::GenericPowerModel{T})
  wr_min, wr_max, wi_min, wi_max = compute_voltage_product_bounds(pm)

  @variable(pm.model, wr_min[bp] <= wr[bp in pm.set.buspair_indexes] <= wr_max[bp], start = getstart(pm.set.buspairs, bp, "wr_start", 1.0)) 
  @variable(pm.model, wi_min[bp] <= wi[bp in pm.set.buspair_indexes] <= wi_max[bp], start = getstart(pm.set.buspairs, bp, "wi_start"))

  return wr, wi
end

function complex_voltage_product_on_off_variables{T}(pm::GenericPowerModel{T})
  wr_min, wr_max, wi_min, wi_max = compute_voltage_product_bounds(pm)

  bi_bp = [i => (b["f_bus"], b["t_bus"]) for (i,b) in pm.set.branches]

  @variable(pm.model, min(0, wr_min[bi_bp[b]]) <= wr[b in pm.set.branch_indexes] <= max(0, wr_max[bi_bp[b]]), start = getstart(pm.set.buspairs, bi_bp[b], "wr_start", 1.0)) 
  @variable(pm.model, min(0, wi_min[bi_bp[b]]) <= wi[b in pm.set.branch_indexes] <= max(0, wi_max[bi_bp[b]]), start = getstart(pm.set.buspairs, bi_bp[b], "wr_start"))

  z = getvariable(pm.model, :line_z)
  for b in pm.set.branch_indexes
    @constraint(pm.model, wr[b] <= z[b]*wr_max[bi_bp[b]])
    @constraint(pm.model, wr[b] >= z[b]*wr_min[bi_bp[b]])

    @constraint(pm.model, wi[b] <= z[b]*wi_max[bi_bp[b]])
    @constraint(pm.model, wi[b] >= z[b]*wi_min[bi_bp[b]])
  end

  return wr, wi
end


function complex_voltage_product_matrix_variables{T}(pm::GenericPowerModel{T})
  wr_min, wr_max, wi_min, wi_max = compute_voltage_product_bounds(pm)

  w_index = 1:length(pm.set.bus_indexes)
  lookup_w_index = [bi => i for (i,bi) in enumerate(pm.set.bus_indexes)]

  @variable(pm.model, WR[1:length(pm.set.bus_indexes), 1:length(pm.set.bus_indexes)], Symmetric)
  @variable(pm.model, WI[1:length(pm.set.bus_indexes), 1:length(pm.set.bus_indexes)])

  # bounds on diagonal
  for (i, bus) in pm.set.buses
    w_idx = lookup_w_index[i]
    wr_ii = WR[w_idx,w_idx]
    wi_ii = WR[w_idx,w_idx]

    setlowerbound(wr_ii, bus["vmin"]^2)
    setupperbound(wr_ii, bus["vmax"]^2)

    #this breaks SCS on the 3 bus exmple
    #setlowerbound(wi_ii, 0)
    #setupperbound(wi_ii, 0)
  end

  # bounds on off-diagonal
  for (i,j) in pm.set.buspair_indexes
    wi_idx = lookup_w_index[i]
    wj_idx = lookup_w_index[j]

    setupperbound(WR[wi_idx, wj_idx], wr_max[(i,j)])
    setlowerbound(WR[wi_idx, wj_idx], wr_min[(i,j)])

    setupperbound(WI[wi_idx, wj_idx], wi_max[(i,j)])
    setlowerbound(WI[wi_idx, wj_idx], wi_min[(i,j)])
  end

  pm.model.ext[:lookup_w_index] = lookup_w_index
  return WR, WI
end


# Creates variables associated with differences in phase angles
function phase_angle_diffrence_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, pm.set.buspairs[bp]["angmin"] <= td[bp in pm.set.buspair_indexes] <= pm.set.buspairs[bp]["angmax"], start = getstart(pm.set.buspairs, bp, "td_start"))
  return td
end

# Creates the voltage magnitude product variables
function voltage_magnitude_product_variables{T}(pm::GenericPowerModel{T})
  vv_min = [bp => pm.set.buspairs[bp]["v_from_min"]*pm.set.buspairs[bp]["v_to_min"] for bp in pm.set.buspair_indexes]
  vv_max = [bp => pm.set.buspairs[bp]["v_from_max"]*pm.set.buspairs[bp]["v_to_max"] for bp in pm.set.buspair_indexes] 

  @variable(pm.model,  vv_min[bp] <= vv[bp in pm.set.buspair_indexes] <=  vv_max[bp], start = getstart(pm.set.buspairs, bp, "vv_start", 1.0))
  return vv
end

function cosine_variables{T}(pm::GenericPowerModel{T})
  cos_min = [bp => -Inf for bp in pm.set.buspair_indexes]
  cos_max = [bp =>  Inf for bp in pm.set.buspair_indexes] 

  for bp in pm.set.buspair_indexes
    buspair = pm.set.buspairs[bp]
    if buspair["angmin"] >= 0
      cos_max[bp] = cos(buspair["angmin"])
      cos_min[bp] = cos(buspair["angmax"])
    end
    if buspair["angmax"] <= 0
      cos_max[bp] = cos(buspair["angmax"])
      cos_min[bp] = cos(buspair["angmin"])
    end
    if buspair["angmin"] < 0 && buspair["angmax"] > 0
      cos_max[bp] = 1.0
      cos_min[bp] = min(cos(buspair["angmin"]), cos(buspair["angmax"]))
    end
  end

  @variable(pm.model, cos_min[bp] <= cs[bp in pm.set.buspair_indexes] <= cos_max[bp], start = getstart(pm.set.buspairs, bp, "cs_start", 1.0))
  return cs
end

function sine_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, sin(pm.set.buspairs[bp]["angmin"]) <= si[bp in pm.set.buspair_indexes] <= sin(pm.set.buspairs[bp]["angmax"]), start = getstart(pm.set.buspairs, bp, "si_start"))
  return si
end

function current_magnitude_sqr_variables{T}(pm::GenericPowerModel{T}) 
  buspairs = pm.set.buspairs
  cm_min = [bp => 0 for bp in pm.set.buspair_indexes] 
  cm_max = [bp => (buspairs[bp]["rate_a"]*buspairs[bp]["tap"]/buspairs[bp]["v_from_min"])^2 for bp in pm.set.buspair_indexes]       

  @variable(pm.model, cm_min[bp] <= cm[bp in pm.set.buspair_indexes] <=  cm_max[bp], start = getstart(pm.set.buspairs, bp, "cm_start"))
  return cm
end



function line_indicator_variables{T}(pm::GenericPowerModel{T})
  @variable(pm.model, 0 <= line_z[l in pm.set.branch_indexes] <= 1, Int, start = getstart(pm.set.branches, l, "line_z_start", 1.0))
  return line_z
end



#=


# Creates variables associated with phase angles at each bus
function phase_angle_variables(m, bus_indexes; start = create_default_start(bus_indexes,0,"theta_start"))
  @variable(m, theta[i in bus_indexes], start = start[i]["theta_start"])
  return theta
end

# TODO: isolate this issue and post a JuMP issue
function phase_angle_variables_1(m, buses)
  @variable(m, theta[b in values(buses)])
  return theta
end


# Create variables associated with voltage magnitudes
function voltage_magnitude_variables(m, buses, bus_indexes; start = create_default_start(bus_indexes, 1.0, "v_start"))
  @variable(m, buses[i]["vmin"] <= v[i in bus_indexes] <= buses[i]["vmax"], start = start[i]["v_start"])
  return v
end

# Creates real generation variables for each generator in the model
function active_generation_variables(m, gens, gen_indexes; start = create_default_start(gen_indexes,0, "pg_start"))
  @variable(m, gens[i]["pmin"] <= pg[i in gen_indexes] <= gens[i]["pmax"], start = start[i]["pg_start"])
  return pg
end

# Creates reactive generation variables for each generator in the model
function reactive_generation_variables(m, gens, gen_indexes; start = create_default_start(gen_indexes,0, "qg_start"))
  @variable(m, gens[i]["qmin"] <= qg[i in gen_indexes] <= gens[i]["qmax"], start = start[i]["qg_start"])
  return qg
end

# Creates generator indicator variables
function generator_indicator_variables(m, gens, gen_indexes; start = create_default_start(gen_indexes,1, "uc_start"))
  @variable(m, 0 <= uc[i in gen_indexes] <= 1, Int, start = start[i]["uc_start"])
  return uc
end


# Creates real load variables for each bus in the model
function active_load_variables(m, buses, bus_indexes; start = create_default_start(bus_indexes,0, "pd_start"))
  pd_min = [i => 0.0 for i in bus_indexes] 
  pd_max = [i => 0.0 for i in bus_indexes] 
  for i in bus_indexes
    if (buses[i]["pd"] >= 0)  
      pd_min[i] = 0
      pd_max[i] = buses[i]["pd"]
    else      
      pd_min[i] = buses[i]["pd"]
      pd_max[i] = 0   
    end
  end    
  @variable(m, pd_min[i] <= pd[i in bus_indexes] <= pd_max[i], start = start[i]["pd_start"])
  return pd
end

# Creates reactive load variables for each bus in the model
function reactive_load_variables(m, buses, bus_indexes; start = create_default_start(bus_indexes,0, "qd_start"))
  qd_min = [i => 0.0 for i in bus_indexes] 
  qd_max = [i => 0.0 for i in bus_indexes] 
  for i in bus_indexes
    if (buses[i]["qd"] >= 0)  
      qd_min[i] = 0.0
      qd_max[i] = buses[i]["qd"]
    else      
      qd_min[i] = buses[i]["qd"]
      qd_max[i] = 0.0   
    end
  end    
  @variable(m, qd_min[i] <= qd[i in bus_indexes] <= qd_max[i], start = start[i]["qd_start"])
  return qd
end

# Create variables associated with real flows on a line... this sets the start value of (l,i,j) annd (l,j,i) to be the same
function line_flow_variables(m, arcs, branches, branch_indexes; tag = "f_start", start = create_default_start(branch_indexes,0,tag))
  @variable(m, -branches[l]["rate_a"] <= f[(l,i,j) in arcs] <= branches[l]["rate_a"], start = start[l][tag])
  return f
end

# Create variables associated with real flows on a line
function line_indicator_variables(m, branch_indexes; start = create_default_start(branch_indexes,1,"z_start"))
  # Bin does not seem to be recognized by gurobi interface
  #@variable(m, z[l in branch_indexes], Bin, start = start)
  @variable(m, 0 <= z[l in branch_indexes] <= 1, Int, start = start[l]["z_start"])
  #@variable(m, z[l in branch_indexes], Int, start = start)
  return z
end

# Create variables for modeling v^2 lifted to w
function voltage_magnitude_sqr_variables(m, buses, bus_indexes; start = create_default_start(bus_indexes,1.001, "w_start"))
  @variable(m, buses[i]["vmin"]^2 <= w[i in bus_indexes] <= buses[i]["vmax"]^2, start = start[i]["w_start"])
  return w
end

function voltage_magnitude_sqr_from_on_off_variables(m, z, branch_indexes, branches, buses; start = create_default_start(branch_indexes,0, "w_from_start"))
  @variable(m, 0 <= w_from[i in branch_indexes] <= buses[branches[i]["f_bus"]]["vmax"]^2, start = start[i]["w_from_start"])

  for i in branch_indexes
    @constraint(m, w_from[i] <= z[i]*buses[branches[i]["f_bus"]]["vmax"]^2)
    @constraint(m, w_from[i] >= z[i]*buses[branches[i]["f_bus"]]["vmin"]^2)
  end

  return w_from
end

function voltage_magnitude_sqr_to_on_off_variables(m, z, branch_indexes, branches, buses; start = create_default_start(branch_indexes,0, "w_to_start"))
  @variable(m, 0 <= w_to[i in branch_indexes] <= buses[branches[i]["t_bus"]]["vmax"]^2, start = start[i]["w_to_start"])

  for i in branch_indexes
    @constraint(m, w_to[i] <= z[i]*buses[branches[i]["t_bus"]]["vmax"]^2)
    @constraint(m, w_to[i] >= z[i]*buses[branches[i]["t_bus"]]["vmin"]^2)
  end

  return w_to
end




# Creates variables associated with cosine terms in the AC power flow models for SOC models
function real_complex_product_on_off_variables(m, z, branch_indexes, branches, buses; start = create_default_start(branch_indexes,0, "wr_start"))
  wr_min = [b => -Inf for b in branch_indexes]
  wr_max = [b =>  Inf for b in branch_indexes] 

  for b in branch_indexes
    branch = branches[b]
    i = branch["f_bus"]
    j = branch["t_bus"]

    if branch["angmin"] >= 0
      wr_max[b] = buses[i]["vmax"]*buses[j]["vmax"]*cos(branch["angmin"])
      wr_min[b] = buses[i]["vmin"]*buses[j]["vmin"]*cos(branch["angmax"])
    end
    if branch["angmax"] <= 0
      wr_max[b] = buses[i]["vmax"]*buses[j]["vmax"]*cos(branch["angmax"])
      wr_min[b] = buses[i]["vmin"]*buses[j]["vmin"]*cos(branch["angmin"])
    end
    if branch["angmin"] < 0 && branch["angmax"] > 0
      wr_max[b] = buses[i]["vmax"]*buses[j]["vmax"]*1.0
      wr_min[b] = buses[i]["vmin"]*buses[j]["vmin"]*min(cos(branch["angmin"]), cos(branch["angmax"]))
    end
  end
  
  @variable(m, min(0, wr_min[b]) <= wr[b in branch_indexes] <= max(0, wr_max[b]), start = start[b]["wr_start"]) 

  for b in branch_indexes
    @constraint(m, wr[b] <= z[b]*wr_max[b])
    @constraint(m, wr[b] >= z[b]*wr_min[b])
  end

  return wr
end

# Creates variables associated with sine terms in the AC power flow models for SOC models
function imaginary_complex_product_on_off_variables(m, z, branch_indexes, branches, buses; start = create_default_start(branch_indexes,0, "wi_start"))
  wi_min = [b => -Inf for b in branch_indexes]
  wi_max = [b =>  Inf for b in branch_indexes] 

  for b in branch_indexes
    branch = branches[b]
    i = branch["f_bus"]
    j = branch["t_bus"]

    if branch["angmin"] >= 0
      wi_max[b] = buses[i]["vmax"]*buses[j]["vmax"]*sin(branch["angmax"])
      wi_min[b] = buses[i]["vmin"]*buses[j]["vmin"]*sin(branch["angmin"])
    end
    if branch["angmax"] <= 0
      wi_max[b] = buses[i]["vmin"]*buses[j]["vmin"]*sin(branch["angmax"])
      wi_min[b] = buses[i]["vmax"]*buses[j]["vmax"]*sin(branch["angmin"])
    end
    if branch["angmin"] < 0 && branch["angmax"] > 0
      wi_max[b] = buses[i]["vmax"]*buses[j]["vmax"]*sin(branch["angmax"])
      wi_min[b] = buses[i]["vmax"]*buses[j]["vmax"]*sin(branch["angmin"])
    end
  end
  
  @variable(m, min(0, wi_min[b]) <= wi[b in branch_indexes] <= max(0, wi_max[b]), start = start[b]["wi_start"])

  for b in branch_indexes
    @constraint(m, wi[b] <= z[b]*wi_max[b])
    @constraint(m, wi[b] >= z[b]*wi_min[b])
  end

  return wi 
end









function complex_product_matrix_variables(m, buspairs, buspair_indexes, buses, bus_indexes)
  w_index = 1:length(bus_indexes)
  lookup_w_index = [bi => i for (i,bi) in enumerate(bus_indexes)]

  wr_min = [bp => -Inf for bp in buspair_indexes] 
  wr_max = [bp =>  Inf for bp in buspair_indexes] 
  wi_min = [bp => -Inf for bp in buspair_indexes] 
  wi_max = [bp =>  Inf for bp in buspair_indexes] 

  for bp in buspair_indexes
      i,j = bp
      buspair = buspairs[bp]
      if buspair["angmin"] >= 0
          wr_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*cos(buspair["angmin"])
          wr_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*cos(buspair["angmax"])
          wi_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmax"])
          wi_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*sin(buspair["angmin"])
      end
      if buspair["angmax"] <= 0
          wr_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*cos(buspair["angmax"])
          wr_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*cos(buspair["angmin"])
          wi_max[bp] = buspair["v_from_min"]*buspair["v_to_min"]*sin(buspair["angmax"])
          wi_min[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmin"])
      end
      if buspair["angmin"] < 0 && buspair["angmax"] > 0
          wr_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*1.0
          wr_min[bp] = buspair["v_from_min"]*buspair["v_to_min"]*min(cos(buspair["angmin"]), cos(buspair["angmax"]))
          wi_max[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmax"])
          wi_min[bp] = buspair["v_from_max"]*buspair["v_to_max"]*sin(buspair["angmin"])
      end
  end

  @variable(m, WR[1:length(bus_indexes), 1:length(bus_indexes)], Symmetric)
  @variable(m, WI[1:length(bus_indexes), 1:length(bus_indexes)])

  # bounds on diagonal
  for (i,bus) in buses
    w_idx = lookup_w_index[i]
    wr_ii = WR[w_idx,w_idx]
    wi_ii = WR[w_idx,w_idx]

    setlowerbound(wr_ii, bus["vmin"]^2)
    setupperbound(wr_ii, bus["vmax"]^2)

    #this breaks SCS on the 3 bus exmple
    #setlowerbound(wi_ii, 0)
    #setupperbound(wi_ii, 0)
  end

  # bounds on off-diagonal
  for (i,j) in buspair_indexes
    wi_idx = lookup_w_index[i]
    wj_idx = lookup_w_index[j]

    setupperbound(WR[wi_idx, wj_idx], wr_max[(i,j)])
    setlowerbound(WR[wi_idx, wj_idx], wr_min[(i,j)])

    setupperbound(WI[wi_idx, wj_idx], wi_max[(i,j)])
    setlowerbound(WI[wi_idx, wj_idx], wi_min[(i,j)])
  end

  return WR, WI, lookup_w_index
end


# creates a default start vector
function create_default_start(indexes, value, tag)
  start = Dict()
  for (i in indexes)
    start[i] = Dict(tag => value)
  end
  return start
end

=#