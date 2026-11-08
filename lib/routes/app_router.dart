import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trainhub/core/di/injection.dart';
import 'package:trainhub/features/fitpro/auth/auth_pages.dart';
import 'package:trainhub/features/fitpro/screens/calendar_page.dart';
import 'package:trainhub/features/fitpro/screens/extra_pages.dart';
import 'package:trainhub/features/fitpro/screens/planned_workouts_page.dart';
import 'package:trainhub/features/fitpro/screens/figma_pages.dart';
import 'package:trainhub/features/fitpro/screens/live_session_page.dart';
import 'package:trainhub/features/fitpro/screens/main_pages.dart';
import 'package:trainhub/features/fitpro/screens/own_workout_page.dart';
import 'package:trainhub/features/fitpro/screens/photo_progress_ui.dart';
import 'package:trainhub/features/fitpro/screens/workout_history_page.dart';
import 'package:trainhub/features/fitpro/screens/exercises_catalog_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer/add_calendar_event_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer/calendar_event_detail_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer/create_exercise_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer/create_program_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer/my_programs_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer/ready_workouts_ui.dart' as trainer_workouts;
import 'package:trainhub/features/fitpro/screens/my_trainer_requests_page.dart';
import 'package:trainhub/features/fitpro/screens/trainer_requests_page.dart';
import 'package:trainhub/features/fitpro/screens/trainers_page.dart';
import 'package:trainhub/features/fitpro/screens/videos/video_pages.dart';
import 'package:trainhub/features/fitpro/shell/fit_shell.dart';
import 'package:trainhub/features/fitpro/timer/timer_page.dart';
import 'package:trainhub/features/splash/presentation/splash_page.dart';
import 'package:trainhub/routes/route_names.dart';

/// Builds the application [GoRouter] with FitPro screens.
GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: getIt(),
    initialLocation: RouteNames.splash,
    routes: [
      GoRoute(path: RouteNames.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: RouteNames.welcome, builder: (_, _) => const WelcomePage()),
      GoRoute(path: RouteNames.role, builder: (_, _) => const RolePage()),
      GoRoute(path: RouteNames.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: RouteNames.register, builder: (_, _) => const RegisterPage()),
      GoRoute(path: RouteNames.profileSetup, builder: (_, _) => const ProfileSetupPage()),
      GoRoute(path: RouteNames.otp, builder: (_, _) => const OtpPage()),
      GoRoute(path: RouteNames.account, builder: (_, _) => const AccountPage()),
      GoRoute(path: RouteNames.addClient, builder: (_, _) => const AddClientPage()),
      GoRoute(
        path: RouteNames.readyWorkouts,
        builder: (_, state) => trainer_workouts.ReadyWorkoutsPage(
          pro: state.uri.queryParameters['pro'] == '1',
          source: state.uri.queryParameters['source'],
          saved: state.uri.queryParameters['saved'] == '1',
        ),
      ),
      GoRoute(
        path: RouteNames.savedWorkouts,
        builder: (_, _) => const trainer_workouts.ReadyWorkoutsPage(saved: true),
      ),
      GoRoute(
        path: RouteNames.programDetail,
        builder: (_, state) {
          final id = state.extra is int ? state.extra as int : int.tryParse('${state.uri.queryParameters['id']}') ?? 0;
          return trainer_workouts.ProgramDetailPage(id: id);
        },
      ),
      GoRoute(path: RouteNames.createExercise, builder: (_, _) => const CreateExercisePage()),
      GoRoute(path: RouteNames.exercisesCatalog, builder: (_, _) => const ExercisesCatalogPage()),
      GoRoute(
        path: RouteNames.calendarEventDetail,
        builder: (_, state) {
          final id = state.extra is int ? state.extra as int : int.tryParse('${state.uri.queryParameters['id']}') ?? 0;
          return CalendarEventDetailPage(eventId: id);
        },
      ),
      GoRoute(
        path: RouteNames.createProgram,
        builder: (_, state) {
          final extra = state.extra;
          final id = extra is int ? extra : int.tryParse('$extra');
          return CreateProgramPage(programId: id != null && id > 0 ? id : null);
        },
      ),
      GoRoute(path: RouteNames.myPrograms, builder: (_, _) => const MyProgramsPage()),
      GoRoute(path: RouteNames.ownWorkout, builder: (_, _) => const OwnWorkoutPage()),
      GoRoute(
        path: RouteNames.addCalendarEvent,
        builder: (_, state) {
          final extra = state.extra;
          DateTime? date;
          TimeOfDay? time;
          int? eventId = int.tryParse(state.uri.queryParameters['eventId'] ?? '');
          var startNow = false;
          if (extra is Map) {
            startNow = extra['startNow'] == true;
            final rawDate = extra['date'];
            final rawTime = extra['time'];
            final rawId = extra['eventId'] ?? extra['id'];
            if (rawDate is DateTime) date = rawDate;
            if (rawTime is TimeOfDay) time = rawTime;
            if (rawId is int) {
              eventId = rawId;
            } else if (rawId is num) {
              eventId = rawId.toInt();
            } else if (rawId != null) {
              eventId ??= int.tryParse('$rawId');
            }
          } else if (extra is DateTime) {
            date = extra;
          } else if (extra is int) {
            eventId = extra;
          } else if (extra is num) {
            eventId = extra.toInt();
          }
          return AddCalendarEventPage(initialDate: date, initialTime: time, eventId: eventId, startNow: startNow);
        },
      ),
      GoRoute(path: RouteNames.plannedWorkouts, builder: (_, _) => const PlannedWorkoutsPage()),
      GoRoute(path: RouteNames.measurements, builder: (_, _) => const MeasurementsPage()),
      GoRoute(path: RouteNames.clients, builder: (_, _) => const ClientsPage()),
      GoRoute(
        path: RouteNames.clientDetail,
        builder: (_, state) => ClientDetailPage(linkId: state.extra is int ? state.extra as int : null, name: state.extra is String ? state.extra as String : ''),
      ),
      GoRoute(path: RouteNames.attention, builder: (_, _) => const AttentionPage()),
      GoRoute(
        path: RouteNames.attentionDetail,
        builder: (_, state) => AttentionDetailPage(client: state.extra! as AttentionClient),
      ),
      GoRoute(path: RouteNames.todayPlan, builder: (_, _) => const TodayPlanPage()),
      GoRoute(path: RouteNames.report, builder: (_, _) => const ReportPage()),
      GoRoute(path: RouteNames.notifications, builder: (_, _) => const NotificationsPage()),
      GoRoute(path: RouteNames.settings, builder: (_, _) => const SettingsPage()),
      GoRoute(path: RouteNames.subscription, builder: (_, _) => const SubscriptionPage()),
      GoRoute(path: RouteNames.manageSub, builder: (_, _) => const ManageSubPage()),
      GoRoute(path: RouteNames.help, builder: (_, _) => const HelpPage()),
      GoRoute(
        path: RouteNames.terms,
        builder: (_, _) => const LegalPage(
          title: 'Условия использования',
          docType: 'terms',
          body:
              'Используя TrainHub, вы соглашаетесь хранить данные клиентов только для тренировочного процесса, не передавать доступы третьим лицам и соблюдать правила зала. Подписка продлевается автоматически, пока вы её не отмените. Сервис предоставляется «как есть»; расписание и рекомендации не заменяют медицинскую консультацию.',
        ),
      ),
      GoRoute(
        path: RouteNames.privacy,
        builder: (_, _) => const LegalPage(
          title: 'Конфиденциальность',
          docType: 'privacy',
          body:
              'Мы храним имя, контакты, замеры и историю тренировок, чтобы показывать прогресс и расписание. Данные не продаются. Вы можете запросить удаление аккаунта в центре помощи. Платёжные реквизиты обрабатывает платёжный провайдер и не сохраняются в приложении целиком.',
        ),
      ),
      GoRoute(path: RouteNames.specialization, builder: (_, _) => const SpecializationPage()),
      GoRoute(path: RouteNames.body, builder: (_, _) => const BodyParamsPage()),
      GoRoute(path: RouteNames.photo, builder: (_, _) => const PhotoProgressPage()),
      GoRoute(path: RouteNames.lastWorkout, builder: (_, _) => const LastWorkoutPage()),
      GoRoute(path: RouteNames.workoutHistory, builder: (_, _) => const WorkoutHistoryPage()),
      GoRoute(
        path: RouteNames.sessionDetail,
        builder: (_, state) {
          final id = state.extra is int ? state.extra as int : int.tryParse('${state.extra}') ?? 0;
          return SessionDetailPage(sessionId: id);
        },
      ),
      GoRoute(path: RouteNames.trainers, builder: (_, _) => const TrainersPage()),
      GoRoute(path: RouteNames.trainerRequests, builder: (_, _) => const TrainerRequestsPage()),
      GoRoute(path: RouteNames.myTrainerRequests, builder: (_, _) => const MyTrainerRequestsPage()),
      GoRoute(path: RouteNames.videoCatalog, builder: (_, _) => const VideoCatalogPage()),
      GoRoute(
        path: RouteNames.videoTopics,
        builder: (_, state) {
          final extra = state.extra is Map ? Map<String, dynamic>.from(state.extra! as Map) : const <String, dynamic>{};
          return VideoTopicsPage(
            categoryId: int.tryParse('${extra['id']}') ?? 0,
            title: extra['title']?.toString() ?? 'Темы',
          );
        },
      ),
      GoRoute(
        path: RouteNames.topicVideos,
        builder: (_, state) {
          final extra = state.extra is Map ? Map<String, dynamic>.from(state.extra! as Map) : const <String, dynamic>{};
          return TopicVideosPage(
            topicId: int.tryParse('${extra['id']}') ?? 0,
            title: extra['title']?.toString() ?? 'Видео',
          );
        },
      ),
      GoRoute(
        path: RouteNames.videoPlayer,
        builder: (_, state) {
          if (state.extra is Map) {
            final extra = Map<String, dynamic>.from(state.extra! as Map);
            return VideoPlayerPage(
              videoId: int.tryParse('${extra['videoId']}') ?? 0,
              assignmentId: int.tryParse('${extra['assignmentId']}'),
            );
          }
          final id = state.extra is int ? state.extra as int : 0;
          return VideoPlayerPage(videoId: id);
        },
      ),
      GoRoute(path: RouteNames.myVideos, builder: (_, _) => const MyVideosPage()),
      GoRoute(
        path: RouteNames.videoCreate,
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return VideoCreatePage(initialVideo: extra);
          }
          if (extra is Map) {
            return VideoCreatePage(initialVideo: Map<String, dynamic>.from(extra));
          }
          return const VideoCreatePage();
        },
      ),
      GoRoute(path: RouteNames.assignedVideos, builder: (_, _) => const AssignedVideosPage()),
      GoRoute(
        path: RouteNames.assignVideos,
        builder: (_, state) {
          final extra = state.extra is Map ? Map<String, dynamic>.from(state.extra! as Map) : const <String, dynamic>{};
          return AssignVideosPage(
            linkId: int.tryParse('${extra['linkId']}') ?? 0,
            clientName: extra['name']?.toString() ?? 'Клиент',
          );
        },
      ),
      GoRoute(
        path: RouteNames.liveSession,
        builder: (_, state) {
          final id = state.extra is int ? state.extra as int : int.tryParse('${state.uri.queryParameters['id']}') ?? 0;
          return LiveSessionPage(sessionId: id);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return FitShell(navigationShell: navigationShell, trainer: false);
        },
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.client, builder: (_, _) => const ClientHomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.clientCalendar, builder: (_, _) => const CalendarPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.clientWorkouts, builder: (_, _) => const WorkoutsPage(trainer: false)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.clientTimer, builder: (_, _) => const TimerPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.clientProfile, builder: (_, _) => const ProfilePage()),
          ]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return FitShell(navigationShell: navigationShell, trainer: true);
        },
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.trainer, builder: (_, _) => const TrainerHomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.trainerCalendar, builder: (_, _) => const CalendarPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.trainerWorkouts, builder: (_, _) => const WorkoutsPage(trainer: true)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.trainerTimer, builder: (_, _) => const TimerPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: RouteNames.trainerProfile, builder: (_, _) => const ProfilePage()),
          ]),
        ],
      ),
    ],
  );
}
