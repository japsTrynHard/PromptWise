import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/verification.dart';

enum DraftReviewAction { approve, reject }

Future<DraftReviewAction?> showVerificationDraftReview(
  BuildContext context,
  VerificationCaseDraft draft,
) => showDialog<DraftReviewAction>(
  context: context,
  builder: (_) => VerificationDraftReview(draft: draft),
);

class VerificationDraftReview extends StatelessWidget {
  final VerificationCaseDraft draft;
  const VerificationDraftReview({super.key, required this.draft});

  @override
  Widget build(BuildContext context) {
    final payload = draft.payload;
    String text(String key) => payload[key]?.toString().trim() ?? '';
    Widget section(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(value.isEmpty ? 'Not supplied in this draft.' : value),
        ],
      ),
    );
    final source = Uri.tryParse(draft.sourceUrl);
    final canOpen =
        source != null && source.scheme == 'https' && source.host.isNotEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Review verification draft',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    section('Title', draft.title),
                    section('Summary', draft.summary),
                    section(
                      'Skill and difficulty',
                      '${draft.subskill.label} · Level ${draft.difficulty} · ${draft.caseType.label}',
                    ),
                    section('Scenario', text('scenario')),
                    section('Claim', text('claim_text')),
                    section(
                      'Original source',
                      '${draft.sourceName}\n${draft.sourceUrl}\nPublished: ${draft.sourcePublishedAt?.toLocal().toString() ?? 'Date not supplied'}',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (canOpen)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open source'),
                            onPressed: () async {
                              var opened = false;
                              try {
                                opened = await launchUrl(
                                  source,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {}
                              if (!opened && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Source could not open. Copy its URL instead.',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        if (draft.sourceUrl.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy source URL'),
                            onPressed: () async {
                              try {
                                await Clipboard.setData(
                                  ClipboardData(text: draft.sourceUrl),
                                );
                              } catch (_) {
                                /* URL remains selectable above. */
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    section('Media details', text('media_description')),
                    section(
                      'Evidence',
                      _entries(
                        payload['evidence'],
                        (entry) =>
                            '${entry['code'] ?? ''} · ${entry['label'] ?? ''}\n${entry['detail'] ?? ''}\nType: ${entry['type'] ?? 'Not supplied'} · Key evidence: ${entry['is_key'] == true ? 'Yes' : 'No'}',
                      ),
                    ),
                    section(
                      'Verification actions',
                      _entries(
                        payload['actions'],
                        (entry) =>
                            '${entry['code'] ?? ''} · ${entry['label'] ?? ''}\n${entry['description'] ?? ''}\nUseful: ${entry['useful'] == true ? 'Yes' : 'No'} · Reveals: ${entry['reveals_evidence_codes'] ?? 'Not supplied'}',
                      ),
                    ),
                    section(
                      'Answer/source choices',
                      _choices(
                        payload['source_options'],
                        payload['best_source_index'],
                      ),
                    ),
                    section('Correct verdict', text('correct_decision')),
                    section('Expected confidence', text('expected_confidence')),
                    section('Explanation', text('explanation')),
                    section('Learning point', text('learning_point')),
                    const Text(
                      'Check the original source and every key before approving. Missing fields are shown as unavailable; this preview does not validate factual accuracy.',
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel review'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, DraftReviewAction.reject),
                    child: const Text('Reject draft'),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, DraftReviewAction.approve),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Approve reviewed case'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _entries(dynamic value, String Function(Map entry) format) =>
    value is List ? value.whereType<Map>().map(format).join('\n\n') : '';
String _choices(dynamic value, dynamic index) {
  if (value is! List) return '';
  return [
    for (var i = 0; i < value.length; i++)
      '${i + 1}. ${value[i]}${index is int && index == i ? ' [keyed source]' : ''}',
  ].join('\n');
}
