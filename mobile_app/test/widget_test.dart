import 'dart:convert';

import 'package:fb_group_poster/main.dart';
import 'package:fb_group_poster/models/app_settings.dart';
import 'package:fb_group_poster/models/fb_account.dart';
import 'package:fb_group_poster/services/poster_runner.dart';
import 'package:fb_group_poster/services/storage_service.dart';
import 'package:fb_group_poster/utils/group_url_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GroupUrlValidator', () {
    test('normalizes desktop and mobile Facebook group URLs', () {
      expect(
        GroupUrlValidator.normalize(
          'https://www.facebook.com/groups/123456789/about',
        ),
        'https://www.facebook.com/groups/123456789/',
      );
      expect(
        GroupUrlValidator.normalize(
          'https://m.facebook.com/groups/my-group?ref=share',
        ),
        'https://www.facebook.com/groups/my-group/',
      );
    });

    test('rejects invalid and placeholder URLs', () {
      expect(
        () => GroupUrlValidator.normalize('https://www.facebook.com/pages/abc'),
        throwsFormatException,
      );
      expect(
        () => GroupUrlValidator.normalize(
          'https://www.facebook.com/groups/YOUR_GROUP_ID_1/',
        ),
        throwsFormatException,
      );
    });

    test('parseMany deduplicates normalized URLs', () {
      final list = GroupUrlValidator.parseMany(
        'https://www.facebook.com/groups/111/\n'
        'https://m.facebook.com/groups/111?ref=1,\n'
        'https://www.facebook.com/groups/222',
      );
      expect(list, [
        'https://www.facebook.com/groups/111/',
        'https://www.facebook.com/groups/222/',
      ]);
    });
  });

  group('AppStateController', () {
    test('persists FB account, default post selection, and bridge start/stop', () async {
      var stopCalled = false;
      var pollCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/start') {
          return http.Response(jsonEncode({'started': true}), 202);
        }
        if (request.url.path == '/stop') {
          stopCalled = true;
          return http.Response(jsonEncode({'stopping': true}), 200);
        }
        if (request.url.path == '/status') {
          pollCount++;
          return http.Response(
            jsonEncode({
              'running': pollCount == 1 && !stopCalled,
              'current_index': 1,
              'total_groups': 1,
              'current_group': 'https://www.facebook.com/groups/111/',
              'logs': ['[INFO] Posted to group 111'],
              'results': [
                {
                  'group': 'https://www.facebook.com/groups/111/',
                  'status': 'posted',
                  'anonymous': true,
                }
              ],
              'last_status': stopCalled ? 'stopped' : 'completed',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final storage = await StorageService.create();
      final controller = AppStateController(storage, httpClient: mockClient)
        ..init();

      await controller.saveAccount(
        const FbAccount(email: 'user@example.com', password: 'secret'),
      );
      expect(controller.account.hasCredentials, isTrue);

      final first = await controller.createPost(
        title: 'First',
        message: 'Hello World',
      );
      final second = await controller.createPost(
        title: 'Second',
        message: 'Second post',
        setAsDefault: false,
      );
      expect(controller.defaultPost?.id, first.id);

      await controller.selectDefaultPost(second.id);
      expect(controller.defaultPost?.id, second.id);

      await controller.addGroupUrls('https://www.facebook.com/groups/111/');
      await controller.updateSettings(
        controller.settings.copyWith(executionMode: ExecutionMode.bridge),
      );

      final runFuture = controller.startScript();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.isRunning, isTrue);
      await controller.stopScript();
      await runFuture;

      expect(stopCalled, isTrue);
      expect(controller.isRunning, isFalse);
      expect(controller.history.length, 1);
      expect(controller.history.first.postTitle, 'Second');
    });
  });

  group('Widget UI', () {
    testWidgets(
      'displays Start/Stop buttons and all side menu screens work',
      (tester) async {
        final storage = await StorageService.create();
        final controller = AppStateController(storage)..init();

        await tester.pumpWidget(FbGroupPosterApp(controller: controller));
        await tester.pumpAndSettle();

        // Main screen has Start and Stop buttons and anonymous mode controls
        expect(find.byKey(const Key('start_script_button')), findsOneWidget);
        expect(find.byKey(const Key('stop_script_button')), findsOneWidget);
        expect(
          controller.settings.anonymousPolicy,
          AnonymousPolicy.preferAnonymous,
        );
        final anonGuardFinder =
            find.byKey(const Key('require_anonymous_if_available_switch'));
        await tester.scrollUntilVisible(
          anonGuardFinder,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(anonGuardFinder);
        await tester.pumpAndSettle();
        expect(anonGuardFinder, findsOneWidget);
        expect(controller.settings.requireAnonymousIfAvailable, isFalse);
        await tester.tap(anonGuardFinder);
        await tester.pumpAndSettle();
        expect(controller.settings.requireAnonymousIfAvailable, isTrue);

        // Open side menu (Drawer)
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.text('FB Account (Email & Password)'), findsOneWidget);
        expect(find.text('Default Post (Create & Select)'), findsOneWidget);
        expect(find.text('Script History'), findsOneWidget);

        // Navigate to FB Account screen and save credentials
        await tester.tap(find.text('FB Account (Email & Password)'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('fb_email_field')),
          'demo@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('fb_password_field')),
          'mySecret123',
        );
        await tester.tap(find.byKey(const Key('save_account_button')));
        await tester.pumpAndSettle();

        expect(controller.account.email, 'demo@example.com');
        expect(controller.account.password, 'mySecret123');

        // Navigate to Default Post screen and create & select a post
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Default Post (Create & Select)'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('create_first_post_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('post_title_field')),
          'Campaign Post',
        );
        await tester.enterText(
          find.byKey(const Key('post_message_field')),
          'Hello Facebook Groups!',
        );
        await tester.tap(find.byKey(const Key('save_post_button')));
        await tester.pumpAndSettle();

        expect(controller.posts.length, 1);
        expect(controller.defaultPost?.title, 'Campaign Post');
        expect(find.text('DEFAULT'), findsOneWidget);

        // Navigate to Script History screen
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Script History'));
        await tester.pumpAndSettle();

        expect(find.text('No script execution history yet.'), findsOneWidget);
      },
    );
  });
}
