# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Delegated: plain static HTML, CSS and minimal JavaScript, chosen for GitHub
Pages, auditability, low maintenance and straightforward localization.

## Users

People who want to run a personal WireGuard endpoint on a dedicated Debian or
Ubuntu server, and technically curious users evaluating whether FAV is mature,
safe and understandable enough to trust.

## Product Purpose

FAV provisions and manages a dedicated WireGuard server over SSH. The website
must help visitors understand what the app does, its limits, how to install and
use it safely, and where to verify the source and security model.

## Positioning

FAV keeps provisioning under the user's control: the app connects directly to
the user's server, verifies its SSH identity, runs inspectable scripts and does
not require a hosted FAV account or control plane.

## Operating Context

Visitors may arrive before downloading the app, while preparing a VPS, during
setup, or while reviewing the project. The canonical technical material lives
in the repository's README, user guide, security model, testing record and
release artifacts.

## Capabilities and Constraints

- English only for the first version, with content paths ready for later locales.
- Static hosting on GitHub Pages; no analytics, cookies, forms or remote fonts.
- The website must not imply that FAV is a VPN client, anonymity service or a
  replacement for provider recovery access.
- Downloads must point to verified release artifacts once the public repository
  exists; unreleased platforms must not appear available.
- FAV is early-release software and must be presented for dedicated servers.

## Brand Commitments

The product name is FAV, expanded as “Free and verifiable VPN provisioner”. The
voice is direct, calm and technically honest. Existing application icons and
the app's purple accent are the available identity assets.

## Evidence on Hand

The repository contains the application source, security model, user guide,
security-testing summary and platform smoke-test record. It has no testimonials,
customer counts or performance benchmarks; none may be fabricated.

## Product Principles

- Explain the mechanism before making claims.
- State safety boundaries where they affect a decision.
- Prefer short, useful instructions to promotional copy.
- Make source, security documentation and recovery guidance easy to find.
- Keep the site private by default: no tracking or unnecessary dependencies.

## Accessibility & Inclusion

The site must support keyboard navigation, reduced motion, high contrast,
responsive layouts and 200% text enlargement. Its structure should allow later
translations without redesigning navigation or page templates.
