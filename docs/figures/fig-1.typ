#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node

#figure(
  block(
    fill: rgb("ffffff"),
    inset: 12pt,
    radius: 6pt,
    diagram(
      node-stroke: 1pt,
      edge-stroke: 1pt,
      spacing: (26mm, 12mm),

      // Spec & Test Layer (Top)
      node(
        (1, 0),
        [*Lune Test Suite*\ `lune run test`],
        corner-radius: 4pt,
        fill: rgb("e8def8"),
        name: <lune>,
      ),

      // Plugin Surface
      node(
        (1, 1),
        [*Plugin Surface*\ (Panel / Service / Widget)],
        corner-radius: 4pt,
        fill: rgb("eaddff"),
        name: <plugin>,
      ),

      // STL Core Layer
      node(
        (1, 2),
        [*STL Modules*\ (Proc, Filesystem, State, Lifecycle)],
        corner-radius: 4pt,
        fill: rgb("ffd8e4"),
        name: <stl>,
      ),

      // Host Bridge
      node(
        (1, 3),
        [*STL Host Bridge*\ (`lib/stl/host.luau`)],
        corner-radius: 4pt,
        fill: rgb("ffd8e4"),
        name: <bridge>,
      ),

      // Mocks Branch (Pushed further left at x = -0.2)
      node(
        (-0.2, 3),
        [*Mock Host Harness*\ Stubs: IPC, UI, `runAsync`],
        corner-radius: 4pt,
        stroke: (paint: black, thickness: 1pt, dash: "dashed"),
        fill: rgb("f9dedc"),
        name: <mock>,
      ),

      // Live Engine (Bottom)
      node(
        (1, 4),
        [*Noctalia Host Runtime*\ Live Shell Engine / Wayland],
        corner-radius: 4pt,
        fill: rgb("e7e0ec"),
        name: <host>,
      ),

      // Main downward spine
      edge(
        <lune>,
        <plugin>,
        "-|>",
        label: [*Drives Lifecycle*],
        label-side: right,
      ),
      edge(<plugin>, <stl>, "-|>", label: [*Consumes*], label-side: right),
      edge(
        <stl>,
        <bridge>,
        "-|>",
        label: [*Resolves Engine*],
        label-side: right,
      ),
      edge(
        <bridge>,
        <host>,
        "-|>",
        label: [*Live Desktop Mode*],
        label-side: right,
      ),

      // Horizontal bidirectional test link between Bridge and Mock
      edge(
        <bridge>,
        <mock>,
        "<|-|>",
        label: [*Headless Mode*],
        stroke: (dash: "dashed"),
        label-side: left,
      ),

      // Outer arc with dedicated clearance
      edge(
        <lune.west>,
        <mock.north>,
        "-|>",
        label: [*Injects Stubs*\ `setInjectedHost()`],
        bend: -30deg,
        stroke: (dash: "dashed"),
        label-side: right,
      ),
    ),
  ),
)
