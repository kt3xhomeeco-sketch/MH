# Implementation Plan: Unified module rules

**Feature**: 005-unified-module-rules | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary
Add a portable semantic-face constraint layer around existing ATT/sample engines. Solve sparse linear plane equations per axis against current geometry. Retain safe ATT evaluation as the preferred engine, with inferred contacts as references; manual constraints are explicit overrides.

## Technical Context
Ruby 3.2 / SketchUp 2025; plain HTML/CSS/JS HtmlDialog; offline WebGL and software depth renderer. JSON storage, Minitest, Electron smoke tests, RuboCop/SketchUp. Maximum 600 panels, bounded constraints and validated references.

## Constitution Check
Pass: own portable core, envelope preservation, ATT priority, private-copy transactions, scoped tooling. No new external service or dependency. Recheck after native validation.

## Project Structure
`rule_system.rb`: schema, inference, conversion, edits and planning.
`plane_solver.rb`: sparse equations, conflict detection.
Existing core/runtime/panel adapters dispatch the new format. UI has a floating tree, ribbon and context editor inside the canvas area. Add runtime sources to lint/package manifests.

## Validation
Portable ordinary-cabinet constraints and DC conversion/regression tests; UI branch/editor/picking and existing pixel occlusion checks; native ordinary fixture and existing readable DC trials with exact owned-copy cleanup and source comparison.
