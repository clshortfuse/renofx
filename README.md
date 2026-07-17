# RenoFX

> **Note:** This is an AI-generated placeholder README.

A ReShade shader port of the `renodx` HDR toolkit, designed to make better HDR image presentation more accessible in ReShade-enabled games.

## Overview

This project ports the work from the `renodx` project into a ReShade shader format. It provides HDR-aware image grading, tone mapping, and presentation controls to help SDR and HDR games better utilize HDR outputs.

The main shader in this repository is:

- `Shaders/RenoFXHDRToolkit.fx`

## Features

- HDR boost and inverse tone mapping for brighter highlights
- Support for SDR and HDR input paths
- Output presentation targeting SDR, HDR10, or scRGB
- Color grading controls with perceptually motivated transforms
- Estimated peak brightness reporting for HDR workflows

## Installation

1. Install ReShade and configure it for your game.
2. Copy `Shaders/RenoFXHDRToolkit.fx` into your ReShade `Shaders` folder.
3. Launch the game and open the ReShade overlay.
4. Enable the `RenoFXHDRToolkit` shader and adjust the settings.

## Usage

- Choose the input transfer mode that matches your game's rendered output.
- Use `Game Brightness` to scale the base image.
- Use `HDR Boost` to expand bright content and create HDR highlights.
- Keep color grading controls at neutral defaults until the HDR boost is correct.
- Match output nits to your display or target HDR presentation pipeline.

## Notes

- `Auto` output presentation is recommended for most use cases.
- Proper input scaling is important for consistent HDR behavior.
- This shader is intended as a portable ReShade version of the `renodx` HDR workflow.

## License

This project is released under the MIT License. See `LICENSE` for details.
