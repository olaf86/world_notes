# RevenueCat TestFlight readiness

Use this checklist before uploading a TestFlight build that must display the
World Notes PRO paywall. Do not record API key values in this document.

## App Store Connect

1. In **Business**, confirm that the latest Paid Applications Agreement is
   active and that tax and banking setup does not require action.
2. Under the World Notes subscription group, confirm that the group has at
   least one localization.
3. Confirm that both subscriptions have complete metadata, pricing,
   availability, and review information:

   - `world_notes_pro_monthly`
   - `world_notes_pro_yearly`

4. Confirm that each subscription is at least **Ready to Submit**. Products in
   that state can be loaded by StoreKit in Sandbox and TestFlight.
5. For the first app release, include both subscriptions, their subscription
   group, and the app version in the same App Review submission. After a
   rejection, confirm that none of these items was removed from the resubmission.

## RevenueCat dashboard

1. Confirm that the iOS app uses bundle ID `dev.asobo.worldnotes` and the public
   SDK key injected into the TestFlight build belongs to that RevenueCat app.
2. In **Product catalog**, confirm that the two App Store products above are
   imported without configuration warnings.
3. Confirm that both products grant the `pro` entitlement.
4. Confirm that the Offering intended for TestFlight contains a monthly and an
   annual Package mapped to the corresponding App Store products.
5. Make that Offering the Default Offering, or ensure the TestFlight customer
   matches the Targeting rule that selects it.
6. Publish a Paywall and attach it to the Offering. Preview the published
   Paywall in the RevenueCat app before testing it in World Notes.
7. Configure functional Terms of Use and Privacy Policy links in the Paywall.

## TestFlight verification

1. Install the newest TestFlight build on a physical device. Delete an older
   installation first if its cached sandbox state makes results ambiguous.
2. Use an Apple sandbox tester whose storefront is included in the products'
   availability.
3. Open **Profile → World Notes PRO** and verify that the Paywall displays.
4. Verify the monthly and annual plans, localized StoreKit prices, purchase
   sheet, cancellation, restore purchases, Terms of Use, and Privacy Policy.
5. Complete a sandbox purchase and confirm that the `pro` entitlement becomes
   active in RevenueCat and World Notes removes PRO restrictions.

## Diagnostic messages

The subscription screen reports setup failures to Crashlytics with the
`[RevenueCat Setup]` prefix:

- `current offering is not configured`: set the Default Offering or correct
  Targeting in RevenueCat.
- `has no available packages`: verify App Store Connect product readiness,
  storefront availability, bundle ID, and Product-to-Package mappings.
- `is missing expected products`: one product was returned and one was not.
  The app displays the available Package and records a non-fatal
  `revenuecat_setup_warning`; repair the missing product before App Review.
- `RevenueCat error ...`: use its error code and underlying message to identify
  the StoreKit or RevenueCat configuration failure.

## References

- [RevenueCat: Apple App Store and TestFlight](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store)
- [RevenueCat: Offerings](https://www.revenuecat.com/docs/offerings/overview)
- [RevenueCat: Paywalls](https://www.revenuecat.com/docs/tools/paywalls)
- [RevenueCat: Submitting an iOS subscription app](https://www.revenuecat.com/docs/test-and-launch/submitting-ios-subscription-app)
