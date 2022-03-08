extern crate lazy_static;

extern crate wgpu;
mod gpu;

use std::thread;

const MAX_NUMBER_CONNECTIONS: usize = 32768;
const MAX_NUMBER_GATES: usize = 8192;

#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Zeroable, bytemuck::Pod, PartialEq)]
pub struct Circuit {
    from: [u32; MAX_NUMBER_CONNECTIONS],
    to: [u32; MAX_NUMBER_CONNECTIONS],
    gate: [u32; MAX_NUMBER_GATES]
}

impl Circuit {
    fn gates(&self) -> Vec<u32> {
        let mut gates = Vec::new();
        for from_value in self.from {
            if from_value != 0 && !gates.contains(&from_value) {
                gates.push(from_value);
            }
        }
        for to_value in self.to {
            if to_value != 0 && !gates.contains(&to_value) {
                gates.push(to_value);
            }
        }
        gates
    }
}

impl Default for Circuit {
    fn default() -> Self {
        let mut gate_array = [0; MAX_NUMBER_GATES];
        gate_array[3] = 1;
        let mut from_array = [0; MAX_NUMBER_CONNECTIONS];
        from_array[0] = 1;
        from_array[1] = 2;
        let mut to_array = [0; MAX_NUMBER_CONNECTIONS];
        to_array[0] = 3;
        to_array[1] = 3;
        Self {
            from: from_array,
            to: to_array,
            gate: gate_array
        }
    }
}

fn run() {
    env_logger::init();
    println!("start");
    let circuit = Circuit::default();
    let gates = circuit.gates();
    for gate in gates {
        for fault in [3, 4] {
            gpu::dispatch(circuit.clone(), gate, fault);
        }
    }
}

fn main() {
    let builder = thread::Builder::new()
                  .name("main".into())
                  .stack_size(256 * 1024 * 1024); // 32MB of stack space

    let handler = builder.spawn(|| {
        run();
    }).unwrap();

    handler.join().unwrap();
}
