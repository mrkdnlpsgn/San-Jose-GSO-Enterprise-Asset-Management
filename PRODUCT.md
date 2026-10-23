# Product

## Register

product

## Users

Two roles, both staff of the General Services Office (GSO) at San Jose Municipal Hall. The office responsible for property custodianship of city-owned assets used across every municipal department:

- **GSO Admin**: full control, manages user accounts, categories, offices, and records; holds deletion authority; reviews AI-generated lifecycle recommendations and disposal justifications before acting on them.
- **GSO Staff**: day-to-day operators. Register assets, log maintenance and disposal events, assign/transfer assets to other departments, run compliance reports. Higher daily usage volume than Admin, needs speed over depth of control.

Other municipal offices (Mayor's Office, ICT Office, etc.) are the *custodial assignees* of tracked assets, not primary users of the system itself: GSO staff act on their behalf.

Both roles require trust in the data they see. Accountability is not optional in a government context.

## Product Purpose

A web and mobile system for the San Jose GSO to manage the full lifecycle of city-owned assets (ICT equipment and beyond) across all municipal departments. Four equally weighted jobs:

1. **Track**, know where every asset is, who is accountable for it, when it was issued or transferred, and which office holds it, from either the desktop app or the field via QR-code mobile lookup.
2. **Lifecycle**, log acquisitions, repairs, and disposals from first receipt to end-of-life, with AI-assisted recommendations (condition- and history-based) advising when an asset should be flagged for repair, disposal, or budget prioritization.
3. **Audit**, generate accurate, COA-compliant accountability reports (RPCPPE, IIRUP) that government auditors can trust without cross-checking by hand.
4. **Verify in the field**: GSO staff carrying the mobile companion app can scan an asset's QR code on-site and immediately see its current status, condition, and history, without returning to a desktop.

Success means zero ambiguity about any asset's status, location, or history, on any device, at any time. An auditor should be able to pull a report and trust every number. An AI recommendation should always be explainable, never a black box the user has to blindly accept.

## Brand Personality

Efficient, approachable, reliable.

The system earns trust by being precise and fast without being intimidating. GSO staff should feel they can move quickly through routine tasks; the interface should never feel like operating machinery that requires training. AI-assisted features should feel like a second opinion offered to a professional, not an authority replacing their judgment. Tone is calm and professional, not sterile or bureaucratic.

## Anti-references

- **Old government portals**: cluttered, dense, hierarchically flat interfaces with poor visual prioritization. No early-2000s government software feel.
- **Generic Bootstrap admin templates**: CoreUI, AdminLTE, and their derivatives. Off-the-shelf blue-and-white templates that signal no design intent.
- **Consumer apps**: social media energy, playful illustration, bright saturated gradients. This is an operational tool for serious daily work.
- **Heavy enterprise (SAP-style)**: overwhelming field density, modals stacking on modals, navigation that requires training to navigate.

## Design Principles

1. **Status at a glance**. A user arriving at any screen should immediately understand the current state without reading. Visual hierarchy does the work, not text labels.
2. **Appropriate formality**, structured and trustworthy enough for government accountability, but never so rigid or dense that staff feel shut out.
3. **Task momentum**, users come with a specific job: register an asset, log a repair, run a report, scan a QR code in the field. The interface should complete that task in the fewest possible steps, on whichever device is at hand.
4. **Audit confidence**. Every action must feel recorded and traceable. Data integrity is a core function, not a detail.
5. **AI as advisor, not oracle**: AI-generated recommendations and summaries are always presented with their rationale, and always sit one step below a human decision, never auto-executed.

## Accessibility & Inclusion

WCAG 2.1 AA compliance. Keyboard navigability for all primary workflows on web. Sufficient contrast for operational environments with mixed lighting conditions (office fluorescent light and outdoor field use via mobile). No reliance on color alone to convey status, condition and lifecycle states pair color with icons/labels.
