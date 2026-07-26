import '../models/lesson.dart';
import '../models/quiz.dart';

final List<Module> modules = [
  Module(
    id: 'mod1',
    title: 'Understanding AI',
    description: 'Learn what AI is, how it works, and its limitations.',
    icon: '\u{1F9E0}',
    lessons: [
      Lesson(
        id: 'les1',
        title: 'What is Artificial Intelligence?',
        content:
            'Artificial Intelligence (AI) refers to computer systems that can perform tasks normally requiring human intelligence. These tasks include understanding language, recognizing images, making decisions, and learning from data. AI works by identifying patterns in large datasets.',
        estimatedMinutes: 5,
      ),
      Lesson(
        id: 'les2',
        title: 'Limitations of AI',
        content:
            'AI is not perfect. It can give incorrect answers, reflect biases present in its training data, and lacks real understanding. Always verify AI-generated information with trusted sources.',
        estimatedMinutes: 5,
      ),
    ],
  ),
  Module(
    id: 'mod2',
    title: 'Prompt Engineering',
    description: 'Practice improving your own prompts through guided feedback.',
    icon: '\u{270D}\u{FE0F}',
    lessons: [
      Lesson(
        id: 'les3',
        title: 'What is a Prompt?',
        content:
            'A prompt is the instruction or question you give to an AI. PromptWise helps you examine clarity, context, specificity, and responsible use. The app gives suggestions, but you remain responsible for revising the prompt using your own words.',
        estimatedMinutes: 4,
      ),
      Lesson(
        id: 'les4',
        title: 'Writing Clear Prompts',
        content:
            'A useful prompt states the task, gives relevant context, identifies the audience, and defines the expected output. PromptWise does not supply a finished corrected prompt. It asks you to review suggestions, revise your own work, and submit another attempt so learning remains active.',
        estimatedMinutes: 6,
      ),
    ],
  ),
  Module(
    id: 'mod3',
    title: 'Ethical AI Usage',
    description: 'Use AI responsibly and avoid misinformation.',
    icon: '\u{2696}\u{FE0F}',
    lessons: [
      Lesson(
        id: 'les5',
        title: 'Responsible AI Practices',
        content:
            'Use AI as an assistant, not a replacement for critical thinking or personal effort. Review suggestions carefully, make your own decisions, verify important information, and credit AI when it contributes significantly to your work.',
        estimatedMinutes: 5,
      ),
      Lesson(
        id: 'les6',
        title: 'Verify Before You Share',
        content:
            'Before sharing an AI-generated claim, check the original source, compare it with reliable references, inspect the publication date, and look for missing context. Responsible verification helps reduce the spread of misinformation in online communities.',
        estimatedMinutes: 6,
      ),
    ],
  ),
];

final List<Quiz> allQuizzes = [
  Quiz(
    question: 'How does AI mainly operate?',
    options: [
      'By exactly copying the human brain',
      'By learning patterns from data',
      'By always giving correct answers',
    ],
    correctIndex: 1,
    explanation:
        'AI learns from data and identifies patterns; it does not always guarantee perfect answers.',
  ),
  Quiz(
    question: 'Which prompt is most effective?',
    options: [
      'Write an essay',
      'Write a 3-paragraph essay about renewable energy for a middle school audience, using simple language.',
      'Essay renewable energy',
    ],
    correctIndex: 1,
    explanation:
        'A detailed prompt with context and audience definition leads to a better response.',
  ),
  Quiz(
    question: 'When should you credit AI?',
    options: [
      'Never',
      'When AI contributed substantially to your work',
      'Always, even for minor grammar checks',
    ],
    correctIndex: 1,
    explanation:
        'Credit AI when it plays a significant role in generating your content.',
  ),
];

int get totalLessonCount =>
    modules.fold(0, (total, module) => total + module.lessons.length);
