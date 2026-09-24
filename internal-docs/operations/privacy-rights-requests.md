# Privacy rights request procedure

This runbook supports the public Privacy Policy. It is an operational guide,
not a place to store an address, identity document, request content, or other
sensitive personal data.

## Scope and owner

- Owner: the World Notes operator, 小川 雄大.
- Intake address: `asobo.support@gmail.com`.
- Covered requests: operator-name, operator-address, security-measure, and
  foreign-processing information; notice of purpose; access; correction;
  addition; deletion; restriction or cessation of use; erasure; cessation of
  third-party provision; and privacy complaints.
- A request may be made by the data subject or a duly authorized
  representative. An unrelated anonymous requester is not treated as the data
  subject for an APPI Article 32 request.

## Intake and timing

1. Acknowledge receipt promptly, with an internal target of five business
   days.
2. Record only the request date, request category, verification state,
   response deadline, outcome, and completion date in the private case log.
   Do not copy request content or identity evidence into source control.
3. Complete the response without undue delay. Use 30 calendar days as the
   normal internal target, or an earlier deadline when applicable law requires
   it. If unusual complexity causes delay, explain the status and revised
   timing to the requester.

## Proportionate verification

Ask only for information proportionate to the request and the data involved.
Prefer, in this order:

1. a request sent from the email address associated with the account;
2. confirmation while signed in to the relevant account;
3. the Firebase user ID together with another account fact already held by the
   service; or
4. a narrowly tailored alternative when the requester no longer has account
   access.

Do not request a government identity document by default. If stronger evidence
is genuinely necessary, explain why, accept the least intrusive evidence that
is sufficient, transmit it through an appropriate channel, limit access, and
delete it when verification and any legally required retention are complete.
For a representative, verify both the data subject and the authority to act.

## Operator identity, safeguards, and foreign processing

- Keep the operator's current legal name in a private operational record,
  outside the public Privacy Policy.
- Keep the operator's current business address in a private operational
  record, outside this repository.
- Confirm that the requester is the data subject or an authorized
  representative before responding to an APPI Article 32 request.
- Send the legal name and address to a verified contact channel without undue
  delay. Do not publish them in a public ticket, repository, or support-thread
  excerpt.
- Provide a useful summary of implemented security safeguards. Exclude details
  whose disclosure could materially weaken authentication, access control,
  abuse prevention, monitoring, or incident response.
- Maintain a private, current inventory of each processor or external service,
  its role, the categories of data involved, the countries or regions where
  data may be processed, the applicable transfer basis, and the contractual or
  technical safeguards relied upon. Confirm the inventory against current
  vendor documentation before responding.
- On a verified request, provide the relevant countries or regions and a
  useful summary of the measures taken without undue delay. Do not disclose
  credentials, infrastructure details, or other information that could impair
  security.
- Review the inventory whenever a provider, hosting region, data flow, or
  contractual protection changes.

## Handling a personal-data request

1. Clarify the requested right and the account, data, period, or processing at
   issue. Help the requester narrow an unclear request without imposing an
   unnecessary burden.
2. Locate data only after verification. Consider the authority Firestore
   database, global projections, Firebase Authentication, Storage, notification
   records, RevenueCat entitlement data, support correspondence, audit and
   safety records, and deletion or retention jobs as applicable.
3. Determine whether applicable law requires the requested action and whether
   an exception applies, including protection of another person's rights,
   security, fraud prevention, legal preservation, or inability to identify
   the requested data.
4. Obtain data from a trusted administrative environment. Redact another
   person's data, secrets, internal security details, and information that the
   law permits or requires the operator to withhold.
5. Respond electronically by default. Explain the result in clear language and
   do not charge a fee under the current policy.
6. If all or part of a request is refused or a different measure is taken,
   provide the reason to the extent legally permitted and record the decision.
7. Record completion, then delete working exports and verification material
   when they are no longer needed.

## Changes to this procedure

Before changing the public request process, fee policy, verification method,
or response channel, update this runbook and the Privacy Policy together. A
material Privacy Policy change must receive a new policy version in both the
Flutter app and Cloud Functions before deployment.

## Primary references

- Personal Information Protection Commission, APPI Guidelines (General
  Rules), section 3-8:
  <https://www.ppc.go.jp/personalinfo/legal/guidelines_tsusoku/>
- PPC FAQ Q9-1, making request procedures known without mandatory continuous
  website publication:
  <https://www.ppc.go.jp/all_faq_index/faq1-q9-1/>
- PPC FAQ Q9-26, proportionate identity verification:
  <https://www.ppc.go.jp/all_faq_index/faq1-q9-26/>
- PPC FAQ Q9-12, responding without undue delay:
  <https://www.ppc.go.jp/all_faq_index/faq1-q9-12/>
