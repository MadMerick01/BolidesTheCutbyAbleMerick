(function () {
  'use strict';

  angular.module('beamng.apps')
    .directive('bolideHudTrialApp', [function () {
      return {
        templateUrl: '/ui/modules/apps/BolideHudTrialApp/app.html',
        restrict: 'EA',
        replace: true,
        scope: true,
        link: function (scope) {
          var defaults = {
            title: 'Bolides: The Cut',
            tagline: 'You transport value, watch the road',
            status: '\u2014',
            instruction: '\u2014',
            threat: 'safe',
            dangerReason: '',
            wallet: 0
          };

          scope.hudTrial = angular.copy(defaults);

          function applyPayload(payload) {
            payload = payload || {};
            scope.hudTrial.title = payload.title || defaults.title;
            scope.hudTrial.tagline = payload.tagline || defaults.tagline;
            scope.hudTrial.status = payload.status || defaults.status;
            scope.hudTrial.instruction = payload.instruction || defaults.instruction;
            scope.hudTrial.threat = payload.threat || defaults.threat;
            scope.hudTrial.dangerReason = payload.dangerReason || '';
            scope.hudTrial.wallet = (payload.wallet === 0 || payload.wallet) ? payload.wallet : defaults.wallet;
          }

          scope.$on('bolideTheCutHudTrialUpdate', function (_event, payload) {
            applyPayload(payload);
          });

          if (window.bngApi && bngApi.engineLua) {
            bngApi.engineLua(
              'if extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.requestHudTrialSnapshot then ' +
                'extensions.bolidesTheCut.requestHudTrialSnapshot(); ' +
              'end'
            );
          }
        }
      };
    }]);
})();
