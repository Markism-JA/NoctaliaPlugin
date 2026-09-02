#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node

#figure(
  diagram(
    node-stroke: 1pt,
    edge-stroke: 1pt,
    spacing: (20mm, 10mm),

    // Ingestion (Top Left)
    node(
      (0, 0),
      [*Upstream Source*\ `src/scripting/*`],
      corner-radius: 4pt,
      fill: rgb("e8def8"),
      name: <upstream>,
    ),

    // Generator (Top Right)
    node(
      (1, 0),
      [*Codegen Script*\ AST / Regex Extractor],
      corner-radius: 4pt,
      fill: rgb("ffd8e4"),
      name: <gen>,
    ),

    // Generated Artifacts (Middle Tier)
    node(
      (0, 1),
      [*Type Definitions*\ `types/noctalia.d.luau`],
      corner-radius: 4pt,
      fill: rgb("eaddff"),
      name: <types>,
    ),
    node(
      (1, 1),
      [*Capability Matrix*\ `matrix.luau`],
      corner-radius: 4pt,
      fill: rgb("eaddff"),
      name: <matrix>,
    ),

    // Downstream Test Suite (Bottom Centered Span)
    node(
      (0.5, 2),
      [*Test CLI & Specs*\ `lune run test_cli`],
      corner-radius: 4pt,
      fill: rgb("f9dedc"),
      name: <tests>,
    ),

    // Step 1: Scan
    edge(<upstream>, <gen>, "-|>", label: [*Scan Tables*], label-side: left),

    // Step 2: Emit Artifacts
    edge(<gen>, <types>, "-|>", label: [*Emit Types*], label-side: left),
    edge(<gen>, <matrix>, "-|>", label: [*Emit Levels*], label-side: right),

    // Step 3: Verify Downstream
    edge(<types>, <tests>, "-|>"),
    edge(<matrix>, <tests>, "-|>"),
  ),
)
