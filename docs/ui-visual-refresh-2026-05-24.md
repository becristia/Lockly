# Lockly UI Visual Refresh - 2026-05-24

## Direction

This pass applies the Calm Security Ops direction to the Flutter app:

- Neutral light canvas with high-contrast ink text.
- Trust blue for primary actions, teal/green for safe states, amber for caution, red for destructive states.
- Tighter card, button, list, and input radii through shared theme/components.
- Less decorative glass and heavy gradients; security state is communicated through badges, icon tiles, and quiet surfaces.
- Shared visual text uses theme surface colors so light and dark themes keep readable contrast.

## Frontend Scope

Changed files:

- `lib/shared/theme/app_theme.dart`
- `lib/shared/widgets/secure_visuals.dart`
- `lib/shared/widgets/secure_panel.dart`
- `lib/features/vault_list/vault_list_page.dart`
- `lib/features/password_generator/password_generator_page.dart`
- `test/ui/visual_system_test.dart`

No cryptography, sync, account, master password, vault storage, or service-call logic was changed.

## Verification

- `flutter analyze`: no issues found.
- `flutter test --reporter compact test\ui\visual_system_test.dart`: 11 tests passed.
- `flutter test --reporter compact`: 481 tests passed.
- Independent frontend UI review found one dark-theme contrast issue; it was fixed and the visual system test now covers the case.

## Follow-Up Notes

The shared `SecureGlassCard` now caps high radii, so legacy pages that pass large radii will visually align without page-by-page edits. Future page work should keep using `AppTheme`, `SecureGlassCard`, `SecureStatusSurface`, `SecureIconTile`, and `SecureStatusPill` rather than adding new hardcoded gradients or one-off colors.
