use std::{borrow::Cow, mem};

use crate::Circuit;
use wgpu::util::DeviceExt;

use lazy_static::lazy_static;

lazy_static! {
    static ref COMPUTE: Compute = pollster::block_on(Compute::new()).unwrap();
}

struct Compute {
    device: wgpu::Device,
    queue: wgpu::Queue
}

impl Compute {
    async fn new() -> Option<Self> {
        let instance: wgpu::Instance = wgpu::Instance::new(wgpu::Backends::all());
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                force_fallback_adapter: false,
                compatible_surface: None,
            })
            .await?;
        println!("{:?}", adapter.get_info());
        let (device, queue) = adapter
        .request_device(
            &wgpu::DeviceDescriptor {
                label: None,
                features: wgpu::Features::empty(),
                limits: wgpu::Limits::downlevel_defaults(),
            },
            None,
        )
        .await
        .unwrap(); 
        Some(Self {
            device,
            queue
        })
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Zeroable, bytemuck::Pod, PartialEq)]
struct WorkPackage {
    circuit: Circuit,
    stuck_at_fault_gate: u32,
    stuck_at_fault_value: u32,
    offset: u32
}

pub fn dispatch(circuit: Circuit, stuck_at_fault_gate: u32, stuck_at_fault_value: u32) -> Vec<u32> {
    let work_package = WorkPackage{circuit, stuck_at_fault_gate, stuck_at_fault_value, offset: 0};
    pollster::block_on(use_gpu(work_package))
}

async fn use_gpu(work_package: WorkPackage) -> Vec<u32> {

    println!("use_gpu");

    let device = &COMPUTE.device;
    let queue = &COMPUTE.queue;

    let shader = device.create_shader_module(&wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(include_str!("shader.wgsl"))),
    });

    println!("shader");

    let compute_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("compute pipeline"),
        layout: None,
        module: &shader,
        entry_point: "main",
    });

    println!("compute pipeline");

    let bind_group_layout = compute_pipeline.get_bind_group_layout(0);

    println!("bind group layout");

    let cpu_buffer_out = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("cpu buffer"),
        size: mem::size_of::<[u32; 256]>() as wgpu::BufferAddress,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::STORAGE,
        mapped_at_creation: false,
    });

    let gpu_buffer_in = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("Work Package Buffer"),
        contents: bytemuck::cast_slice(&[work_package]),
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC,
    });

    let gpu_buffer_out = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("gpu buffer"),
        size: mem::size_of::<[u32; 256]>() as wgpu::BufferAddress,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::MAP_WRITE,
        mapped_at_creation: false,
    });

    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: None,
        layout: &bind_group_layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: gpu_buffer_in.as_entire_binding(),
        },
        wgpu::BindGroupEntry {
            binding: 1,
            resource: gpu_buffer_out.as_entire_binding(),
        }],
    });

    println!("bind group");

    let mut command_encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });

    {
        let mut compute_pass = command_encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: None });
        compute_pass.set_pipeline(&compute_pipeline); 
        compute_pass.set_bind_group(0, &bind_group, &[]);
        compute_pass.insert_debug_marker("compute pass");
        compute_pass.dispatch(1, 1, 1); // Number of cells to run, the (x,y,z) size of item being processed
    }

    command_encoder.copy_buffer_to_buffer(&gpu_buffer_out, 0, &cpu_buffer_out, 0, mem::size_of::<[u32; 256]>() as wgpu::BufferAddress);

    println!("before submit");

    queue.submit(Some(command_encoder.finish()));

    println!("after submit");

    let cpu_buffer_out_slice = cpu_buffer_out.slice(..);
    let cpu_buffer_out_future = cpu_buffer_out_slice.map_async(wgpu::MapMode::Read);

    device.poll(wgpu::Maintain::Wait);

    if let Ok(()) = cpu_buffer_out_future.await {
        let result: Vec<u32> = bytemuck::cast_slice(&cpu_buffer_out_slice.get_mapped_range()).to_vec();
        cpu_buffer_out.unmap();
        result
    } else {
        panic!("failed to run compute on gpu!")
    }
}