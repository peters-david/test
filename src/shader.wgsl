let MAX_CONNECTIONS_NUMBER: u32 = 32768u;
let MAX_GATES_NUMBER: u32 = 8192u;

struct Circuit {
    from: array<u32, MAX_CONNECTIONS_NUMBER>;
    to: array<u32, MAX_CONNECTIONS_NUMBER>;
    gate: array<u32, MAX_GATES_NUMBER>;
};

struct WorkPackage {
    circuit: Circuit;
    stuck_at_fault_gate: u32;
    stuck_at_fault_value: u32;
    offset: u32;
};

@group(0)
@binding(0)
var<storage> work_package: WorkPackage;

@group(0)
@binding(1)
var<storage, read_write> output: array<u32, 256>;

var<private> id: u32;
var<private> decisions: u32;
var<private> decision_level: u32;
var<private> primary: array<u32, MAX_GATES_NUMBER>;
var<private> secondary: array<u32, MAX_GATES_NUMBER>;
var<private> array_under_test: array<u32, MAX_GATES_NUMBER>;

fn success() {
    output[id] = 1u;
}

fn failure() {
    output[id] = 0u;
}

fn was_failure() -> bool {
    return output[id] == 0u;
}

fn error() {
    output[id] = 2u;
}

fn was_error() -> bool {
    return output[id] == 2u;
}

fn u32_ceil(x: f32) -> u32 {
    var remainder: f32 = x % 1.0;
    if (remainder == 0.0) {
        return u32(x);
    } else {
        return u32(x - remainder + 1.0);
    }
}

fn invert(value:  u32) -> u32 {
    if (value == 0u) {
        return 1u;
    } else {
        return 0u;
    }
}

fn array_length(a: array<u32, MAX_GATES_NUMBER>) -> u32 {
    array_under_test = a;
    var len: u32 = 0u;
    for (var i: u32 = 0u; i < MAX_GATES_NUMBER; i += 1u) {
        if (array_under_test[i - 1u] != 0u) {
            len = i + 1u;
        }
    }
    return len;
}

fn is_primary_input(gate: u32) -> bool {
    return work_package.circuit.gate[gate] == 0u;
}

fn all_values_are(a: array<u32, MAX_GATES_NUMBER>, l: u32, value: u32) -> bool {
    array_under_test = a;
    for (var i: u32 = 0u; i < l; i += 1u) {
        if (array_under_test[i] != value) {
            return false;
        }
    }
    return true;
}

fn any_value_is(a: array<u32, MAX_GATES_NUMBER>, l: u32, value: u32) -> bool {
    array_under_test = a;
    for (var i: u32 = 0u; i < l; i += 1u) {
        if (array_under_test[i] == value) {
            return true;
        }
    }
    return false;
}

fn from_gates(objective: u32) -> array<u32, MAX_GATES_NUMBER> {
    var froms: array<u32, MAX_GATES_NUMBER>;
    for (var i: u32 = 0u; i < MAX_GATES_NUMBER; i += 1u) {
        froms[i] = 0u;
    }
    var froms_i: u32 = 0u;
    for (var i: u32 = 0u; i < MAX_CONNECTIONS_NUMBER; i += 1u) {
        if (work_package.circuit.to[i] == objective) {
            froms[froms_i] = work_package.circuit.from[i];
            froms_i += 1u;
        }
    }
    return froms;
}

fn unset_from_gates(objective: u32) -> array<u32, MAX_GATES_NUMBER> {
    var all_froms: array<u32, MAX_GATES_NUMBER> = from_gates(objective);
    var all_froms_array_length: u32 = array_length(all_froms);
    var unset_froms: array<u32, MAX_GATES_NUMBER>;
    for (var i: u32 = 0u; i < MAX_GATES_NUMBER; i += 1u) {
        unset_froms[i] = 0u;
    }
    var unset_froms_i: u32 = 0u;
    for (var i: u32 = 0u; i < all_froms_array_length; i += 1u) {
        var gate: u32 = all_froms[i];
        if (primary[gate] == 2u && secondary[gate] == 2u) {
            unset_froms[unset_froms_i] = gate;
            unset_froms_i += 1u;
        }
    }
    return unset_froms;
}

fn to_gates(objective: u32) -> array<u32, MAX_GATES_NUMBER> {
    var tos: array<u32, MAX_GATES_NUMBER>;
    for (var i: u32 = 0u; i < MAX_GATES_NUMBER; i += 1u) {
        tos[i] = 0u;
    }
    var tos_i: u32 = 0u;
    for (var i: u32; i < MAX_CONNECTIONS_NUMBER; i += 1u) {
        if (work_package.circuit.from[i] == objective) {
            tos[tos_i] = work_package.circuit.to[i];
            tos_i += 1u;
        }
    }
    return tos;
}

fn unset_to_gates(objective: u32) -> array<u32, MAX_GATES_NUMBER> {
    var all_tos: array<u32, MAX_GATES_NUMBER> = to_gates(objective);
    var all_tos_array_length: u32 = array_length(all_tos);
    var unset_tos: array<u32, MAX_GATES_NUMBER>;
    for (var i: u32 = 0u; i < MAX_GATES_NUMBER; i += 1u) {
        unset_tos[i] = 0u;
    }
    var unset_tos_i: u32 = 0u;
    for (var i: u32 = 0u; i < all_tos_array_length; i += 1u) {
        var gate: u32 = all_tos[i];
        if (primary[gate] == 2u && secondary[gate] == 2u) {
            unset_tos[unset_tos_i] = gate;
            unset_tos_i += 1u;
        }
    }
    return unset_tos;
}

fn is_primary_output(objective: u32) -> bool {
    var tos: array<u32, MAX_GATES_NUMBER> = to_gates(objective);
    return array_length(tos) == 0u;
}

fn make_decision(decision_depth: u32) -> u32 {
    if (decision_depth > 32u - decision_level) {
        error();
        return 0u;
    }
    var decision: u32 = 0u;
    for (var i: u32 = 0u; i < decision_depth; i += 1u) {
        decision = decision | ((decisions & (1u << (decision_level + i))) >> decision_level);
    }
    decision_level += decision_depth;
    return decision;
}

fn primary_values(a: array<u32, MAX_GATES_NUMBER>, l: u32) -> array<u32, MAX_GATES_NUMBER> {
    array_under_test = a;
    var primaries: array<u32, MAX_GATES_NUMBER>;
    for (var i: u32 = 0u; i < l; i += 1u) {
        var gate: u32 = array_under_test[i];
        primaries[i] = primary[gate];
    }
    return primaries;
}

fn secondary_values(a: array<u32, MAX_GATES_NUMBER>, l: u32) -> array<u32, MAX_GATES_NUMBER> {
    array_under_test = a;
    var secondaries: array<u32, MAX_GATES_NUMBER>;
    for (var i: u32 = 0u; i < l; i += 1u) {
        var gate: u32 = array_under_test[i];
        secondaries[i] = secondary[gate];
    }
    return secondaries;
}

//["inpt", "and", "or", "nand", "nor", "xor", "xnor", "not", "buff"]
//3: 0/1
//4: 1/0
fn is_satisfied(objective: u32) -> bool {
    var froms: array<u32, MAX_GATES_NUMBER> = from_gates(objective);
    var froms_array_length: u32 = array_length(froms);
    var gate_type = work_package.circuit.gate[objective];
    var gate_value: u32 = primary[objective];
    var secondaries: array<u32, MAX_GATES_NUMBER> = secondary_values(froms, froms_array_length);
    if (gate_type == 0u) {
            return true;
    } else if (gate_type == 1u) {
        if (gate_value == 0u) {
            return any_value_is(secondaries, froms_array_length, 0u);
        } else if (gate_value == 1u) {
            return all_values_are(secondaries, froms_array_length, 1u);
        } else {
            error();
            return false;
        }
    } else if (gate_type == 2u) {
        if (gate_value == 0u) {
            return all_values_are(secondaries, froms_array_length, 0u);
        } else if (gate_value == 1u) {
            return any_value_is(secondaries, froms_array_length, 1u);
        } else {
            error();
            return false;
        }
    } else if (gate_type == 3u) {
        if (gate_value == 0u) {
            return all_values_are(secondaries, froms_array_length, 1u);
        } else if (gate_value == 1u) {
            return any_value_is(secondaries, froms_array_length, 0u);
        } else {
            error();
            return false;
        }
    } else if (gate_type == 4u) {
        if (gate_value == 0u) {
            return any_value_is(secondaries, froms_array_length, 1u);
        } else if (gate_value == 1u) {
            return all_values_are(secondaries, froms_array_length, 0u);
        } else {
            error();
            return false;
        }
    } else if (gate_type == 5u) {
        return bool(invert(u32(any_value_is(secondaries, froms_array_length, 2u))));
    } else if (gate_type == 6u) {
        return bool(invert(u32(any_value_is(secondaries, froms_array_length, 2u))));
    } else if (gate_type == 7u) {
        return gate_value == invert(secondaries[0u]);
    } else if (gate_type == 8u) {
        return gate_value == secondaries[0u];
    } else {
        error();
        return false;
    }
}

fn new_backward_gate(objective: u32) -> u32 {
    var froms: array<u32, MAX_GATES_NUMBER> = unset_from_gates(objective);
    var froms_array_length: u32 = array_length(froms);
    var decision_depth: u32 = u32_ceil(log2(f32(froms_array_length)));
    var decision: u32 = make_decision(decision_depth);
    if (decision > froms_array_length) {
        error();
    }
    return froms[decision];
}

fn new_forward_gate(objective: u32) -> u32 {
    var all_tos: array<u32, MAX_GATES_NUMBER> = to_gates(objective);
    var all_tos_array_length: u32 = array_length(all_tos);
    for (var i: u32 = 0u; i < all_tos_array_length; i += 1u) {
        var gate: u32 = all_tos[i];
        if (primary[gate] != 2u && secondary[gate] != 2u) {
            return all_tos[i];
        }
    }
    var tos: array<u32, MAX_GATES_NUMBER> = unset_to_gates(objective);
    var tos_array_length: u32 = array_length(tos);
    var decision_depth: u32 = u32_ceil(log2(f32(tos_array_length)));
    var decision: u32 = make_decision(decision_depth);
    if (decision > tos_array_length) {
        error();
    }
    return tos[decision];
}

fn justify_path(objective: u32, new_gate: u32) {
    var value_to_justify: u32 = primary[objective];
    var gate_type: u32 = work_package.circuit.gate[objective];
    if (gate_type == 1u) {
        primary[new_gate] = value_to_justify;
        secondary[new_gate] = value_to_justify;
    } else if (gate_type == 2u) {
        primary[new_gate] = value_to_justify;
        secondary[new_gate] = value_to_justify;
    } else if (gate_type == 3u) {
        primary[new_gate] = invert(value_to_justify);
        secondary[new_gate] = invert(value_to_justify);
    } else if (gate_type == 4u) {
        primary[new_gate] = invert(value_to_justify);
        secondary[new_gate] = invert(value_to_justify);
    } else if (gate_type == 5u) {
        var decision: u32 = make_decision(1u);
        primary[new_gate] = decision;
        secondary[new_gate] = decision;
    } else if (gate_type == 6u) {
        var decision: u32 = make_decision(1u);
        primary[new_gate] = invert(decision);
        secondary[new_gate] = invert(decision);
    } else if (gate_type == 7u) {
        primary[new_gate] = invert(value_to_justify);
        secondary[new_gate] = invert(value_to_justify);
    } else if (gate_type == 8u) {
        primary[new_gate] = value_to_justify;
        secondary[new_gate] = value_to_justify;
    }
}

//["inpt", "and", "or", "nand", "nor", "xor", "xnor", "not", "buff"]
//3: 0/1
//4: 1/0
fn correct_propagation(objective: u32) -> bool {
    var objective_value: u32 = primary[objective];
    var froms: array<u32, MAX_GATES_NUMBER> = from_gates(objective);
    var froms_array_length: u32 = array_length(froms);
    var gate_type: u32 = work_package.circuit.gate[objective];
    var secondaries: array<u32, MAX_GATES_NUMBER> = secondary_values(froms, froms_array_length);
    if (gate_type == 0u) {
        var from: u32 = froms[0];
        return secondary[0u] == objective_value;
    } else if (gate_type == 1u) {
        if (any_value_is(secondaries, froms_array_length, 0u)) {
            return objective_value == 0u;
        } else if (all_values_are(secondaries, froms_array_length, 1u)) {
            return objective_value == 1u;
        } else {
            error();
            return false;
        }
    } else if (gate_type == 2u) {
        if (any_value_is(secondaries, froms_array_length, 1u)) {
            return objective_value == 1u;
        } else if (all_values_are(secondaries, froms_array_length, 0u)) {
            return objective_value == 0u;
        } else {
            error();
            return false;
        }
    } else if (gate_type == 3u) {
        if (any_value_is(secondaries, froms_array_length, 0u)) {
            return objective_value == 1u;
        } else if (all_values_are(secondaries, froms_array_length, 1u)) {
            return objective_value == 0u;
        } else {
            error();
            return false;
        }
    } else if (gate_type == 4u) {
        if (any_value_is(secondaries, froms_array_length, 1u)) {
            return objective_value == 0u;
        } else if (all_values_are(secondaries, froms_array_length, 0u)) {
            return objective_value == 1u;
        } else {
            error();
            return false;
        }
    } else if (gate_type == 5u) {
        return true; //TODO depends on inputs
    } else if (gate_type == 6u) {
        return true; //TODO depends on inputs
    } else if (gate_type == 7u) {
        return secondaries[0u] == invert(objective_value);
    } else if (gate_type == 8u) {
        return secondaries[0u] == objective_value;
    } else {
        error();
        return false;
    }
}

fn propagate_path(objective: u32, new_gate: u32) {
    var primary_value_to_propagate: u32 = primary[objective];
    var secondary_value_to_propagate: u32 = secondary[objective];
    var gate_type: u32 = work_package.circuit.gate[objective];
    if (gate_type == 0u) {
        primary[new_gate] = primary_value_to_propagate;
        secondary[new_gate] = secondary_value_to_propagate;
    } else if (gate_type == 1u) {
        primary[new_gate] = primary_value_to_propagate;
        secondary[new_gate] = secondary_value_to_propagate;
    } else if (gate_type == 2u) {
        primary[new_gate] = primary_value_to_propagate;
        secondary[new_gate] = secondary_value_to_propagate;
    } else if (gate_type == 3u) {
        primary[new_gate] = invert(primary_value_to_propagate);
        secondary[new_gate] = invert(secondary_value_to_propagate);
    } else if (gate_type == 4u) {
        primary[new_gate] = invert(primary_value_to_propagate);
        secondary[new_gate] = invert(secondary_value_to_propagate);
    } else if (gate_type == 5u) {
        primary[new_gate] = make_decision(1u); //TODO depends on inputs
        //secondary
    } else if (gate_type == 6u) {
        primary[new_gate] = invert(make_decision(1u)); // invert is not needed, TODO depends on inputs
        //secondary
    } else if (gate_type == 7u) {
        primary[new_gate] = invert(primary_value_to_propagate);
        secondary[new_gate] = invert(secondary_value_to_propagate);
    } else if (gate_type == 8u) {
        primary[new_gate] = primary_value_to_propagate;
        secondary[new_gate] = secondary_value_to_propagate;
    } else {
        error();
    }
}

fn init(global_id: u32) -> u32 {
    id = global_id;
    output[global_id] = 10u;
    decisions = id + work_package.offset;
    for (var i: u32 = 0u; i < MAX_GATES_NUMBER; i += 1u) {
        primary[i] = 2u;
        secondary[i] = 2u;
    }
    if (work_package.stuck_at_fault_value == 3u) {
        primary[work_package.stuck_at_fault_gate] = 0u;
        secondary[work_package.stuck_at_fault_gate] = 1u;
    } else if (work_package.stuck_at_fault_value == 4u) {
        primary[work_package.stuck_at_fault_gate] = 1u;
        secondary[work_package.stuck_at_fault_gate] = 0u;
    }
    decision_level = 0u;
    return work_package.stuck_at_fault_gate;
}

fn calc(id: u32) {
    var objective: u32 = init(id);
    for (var i: u32 = 0u; i < 1u; i += 1u) {
        if (!is_satisfied(objective)) {
            //choose new backward gate based on already set inputs and decision
            //set input (xor: based on decision)
            //move objective one closer to input
            var new_gate: u32 = new_backward_gate(objective);
            if (was_error()) {
                return;
            }
            if (primary[new_gate] == 2u && secondary[new_gate] == 2u) {
                justify_path(objective, new_gate);
                if (was_error() || was_failure()) {
                    return;
                }
            } else if (correct_propagation(objective)) {
                //already justified
            } else {
                failure();
                return;
            }
            objective = new_gate;
        } else {
            //if objective has no outputs return true
            //if there already is a propagated path choose it
            //else choose a path based on decision and propagate the output
            //move objective one closer to output
            if (was_error() || was_failure()) {
                return;
            }
            if (is_primary_output(objective)) {
                success();
                return;
            }
            var new_gate: u32 = new_forward_gate(objective);
            if (was_error()) {
                return;
            }
            if (primary[new_gate] == 2u && secondary[new_gate] == 2u) {
                propagate_path(objective, new_gate);
                if (was_error() || was_failure()) {
                    return;
                }
            } else if (correct_propagation(new_gate)) {
                //already propagated
            } else {
                failure();
                return;
            }
            objective = new_gate;
        }
    }
}

@stage(compute)
@workgroup_size(256, 1, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    calc(id.x);
}
