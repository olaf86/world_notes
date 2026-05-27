import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

initializeApp();

const perspectiveApiKey = defineSecret('PERSPECTIVE_API_KEY');

// Threshold above which a message is auto-hidden.
const TOXICITY_THRESHOLD = 0.85;
const SEVERE_TOXICITY_THRESHOLD = 0.70;
const SEXUALLY_EXPLICIT_THRESHOLD = 0.80;

// Auto-hide when report count reaches this number while awaiting review.
const REPORT_THRESHOLD = 5;

interface AttributeScore {
  summaryScore: { value: number };
}

interface PerspectiveResponse {
  attributeScores: {
    TOXICITY?: AttributeScore;
    SEVERE_TOXICITY?: AttributeScore;
    SEXUALLY_EXPLICIT?: AttributeScore;
  };
}

async function isToxic(text: string, apiKey: string): Promise<boolean> {
  if (!text.trim()) return false;

  const res = await fetch(
    `https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        comment: { text },
        requestedAttributes: {
          TOXICITY: {},
          SEVERE_TOXICITY: {},
          SEXUALLY_EXPLICIT: {},
        },
        // Support both Japanese and English content.
        languages: ['ja', 'en'],
        doNotStore: true,
      }),
    }
  );

  if (!res.ok) {
    console.error('Perspective API error', res.status, await res.text());
    return false;
  }

  const data = (await res.json()) as PerspectiveResponse;
  const toxicity = data.attributeScores.TOXICITY?.summaryScore.value ?? 0;
  const severeToxicity =
    data.attributeScores.SEVERE_TOXICITY?.summaryScore.value ?? 0;
  const sexuallyExplicit =
    data.attributeScores.SEXUALLY_EXPLICIT?.summaryScore.value ?? 0;

  return (
    toxicity >= TOXICITY_THRESHOLD ||
    severeToxicity >= SEVERE_TOXICITY_THRESHOLD ||
    sexuallyExplicit >= SEXUALLY_EXPLICIT_THRESHOLD
  );
}

/**
 * Triggered when a new message is created.
 * Checks content via the Perspective API and hides toxic messages.
 *
 * Deploy:
 *   firebase functions:secrets:set PERSPECTIVE_API_KEY
 *   firebase deploy --only functions
 */
export const onMessageCreated = onDocumentCreated(
  { document: 'messages/{messageId}', secrets: [perspectiveApiKey] },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const content = (data['content'] as string) ?? '';
    const apiKey = perspectiveApiKey.value();

    if (!apiKey) {
      console.warn('PERSPECTIVE_API_KEY not set — skipping moderation');
      return;
    }

    let shouldHide = false;
    try {
      shouldHide = await isToxic(content, apiKey);
    } catch (err) {
      console.error('Moderation check failed', err);
      return;
    }

    if (shouldHide) {
      await getFirestore()
        .collection('messages')
        .doc(event.params['messageId'])
        .update({
          isVisible: false,
          moderatedAt: FieldValue.serverTimestamp(),
          moderationReason: 'auto_toxicity',
        });
      console.log(`Auto-hid message ${event.params['messageId']}`);
    }
  }
);

/**
 * Triggered when a report is created.
 * Auto-hides messages that accumulate REPORT_THRESHOLD pending reports.
 */
export const onReportCreated = onDocumentCreated(
  'reports/{reportId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const messageId = data['messageId'] as string;
    if (!messageId) return;

    const messageRef = getFirestore().collection('messages').doc(messageId);
    const messageSnap = await messageRef.get();
    if (!messageSnap.exists) return;

    const msgData = messageSnap.data();
    if (!msgData) return;

    // Already hidden — nothing more to do.
    if (msgData['isVisible'] === false) return;

    const reportCount = (msgData['reportCount'] as number) ?? 0;
    if (reportCount >= REPORT_THRESHOLD) {
      await messageRef.update({
        isVisible: false,
        moderatedAt: FieldValue.serverTimestamp(),
        moderationReason: 'report_threshold',
      });
      console.log(`Auto-hid message ${messageId} after ${reportCount} reports`);
    }
  }
);
