(function () {
  'use strict';

  angular.module('beamng.apps')
    .directive('bolideHudTrialApp', ['$timeout', function ($timeout) {
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
            threat: 'safe',
            dangerReason: '',
            wallet: 0,
            weapons: [],
            equippedWeapon: null,
            paused: false,
            preloaded: false,
            preloadAvailable: false
          };

          var weaponLimits = {
            emp: 5,
            pistol: 6
          };
          var lastWeaponSignature = {};

          scope.hudTrial = angular.copy(defaults);
          scope.weaponButtonHover = {
            id: null,
            active: false
          };
          scope.popup = {
            active: false,
            title: '',
            body: '',
            continueLabel: 'Continue',
            canContinue: true,
            statusLine: ''
          };

          function updateWeaponButtonHoverState() {
            if (!(window.bngApi && bngApi.engineLua)) {
              return;
            }
            var shouldBlock = scope.weaponButtonHover.active
              && scope.hudTrial.equippedWeapon === scope.weaponButtonHover.id;
            bngApi.engineLua("extensions.bolidesTheCut.setHudWeaponButtonHover(" + (shouldBlock ? "true" : "false") + ")");
          }

          function weaponImage(id, ammo, hasWeapon) {
            var safeId = id === 'emp' ? 'emp' : 'pistol';
            var safeAmmo = Math.max(0, Number(ammo || 0));
            var limit = weaponLimits[safeId];
            if (limit !== undefined) {
              safeAmmo = Math.min(safeAmmo, limit);
            }
            var base = hasWeapon ? safeId : safeId + 'none';
            return {
              id: safeId,
              ammo: safeAmmo,
              hasWeapon: hasWeapon,
              src: '/art/ui/bolides_the_cut/' + base + safeAmmo + 'ammo.svg',
              alt: (safeId === 'emp' ? 'EMP' : 'Pistol') + ' ammo'
            };
          }

          function buildWeaponDisplay(weapons) {
            var byId = {};
            (weapons || []).forEach(function (weapon) {
              if (weapon && weapon.id) {
                byId[weapon.id] = weapon;
              }
            });
            var emp = byId.emp;
            var pistol = byId.pistol;
            return [
              weaponImage('emp', emp ? emp.ammo : 0, !!emp),
              weaponImage('pistol', pistol ? pistol.ammo : 0, !!pistol)
            ].map(function (weapon) {
              var signature = (weapon.hasWeapon ? '1' : '0') + ':' + weapon.ammo;
              var changed = signature !== lastWeaponSignature[weapon.id];
              lastWeaponSignature[weapon.id] = signature;
              weapon.animate = changed;
              return weapon;
            });
          }

          function applyPayload(payload) {
            payload = payload || {};
            scope.hudTrial.title = payload.title || defaults.title;
            scope.hudTrial.tagline = payload.tagline || defaults.tagline;
            scope.hudTrial.status = payload.status || defaults.status;
            scope.hudTrial.threat = payload.threat || defaults.threat;
            scope.hudTrial.dangerReason = payload.dangerReason || '';
            scope.hudTrial.wallet = (payload.wallet === 0 || payload.wallet) ? payload.wallet : defaults.wallet;
            scope.hudTrial.weapons = buildWeaponDisplay(payload.weapons || defaults.weapons);
            scope.hudTrial.equippedWeapon = payload.equippedWeapon || null;
            scope.hudTrial.paused = payload.paused === true;
            scope.hudTrial.preloaded = payload.preloaded === true;
            scope.hudTrial.preloadAvailable = payload.preloadAvailable === true;
            updateWeaponButtonHoverState();
            scope.hudTrial.weapons.forEach(function (weapon) {
              if (!weapon.animate) {
                return;
              }
              $timeout(function () {
                weapon.animate = false;
              }, 320, false);
            });
          }

          scope.$on('bolideTheCutHudTrialUpdate', function (_event, payload) {
            applyPayload(payload);
          });

          scope.$on('bolideTheCutPopupUpdate', function (_event, payload) {
            payload = payload || {};
            scope.popup.active = payload.active === true;
            scope.popup.title = payload.title || '';
            scope.popup.body = payload.body || '';
            scope.popup.continueLabel = payload.continueLabel || 'Continue';
            scope.popup.canContinue = payload.canContinue !== false;
            scope.popup.statusLine = payload.statusLine || '';
          });

          scope.toggleEquip = function (weaponId) {
            if (!weaponId) {
              return;
            }
            if (window.bngApi && bngApi.engineLua) {
              bngApi.engineLua("extensions.bolidesTheCut.toggleHudWeapon('" + weaponId + "')");
            }
          };

          scope.setEquipButtonHover = function (weaponId, isHovering) {
            scope.weaponButtonHover.id = weaponId || null;
            scope.weaponButtonHover.active = !!isHovering;
            updateWeaponButtonHoverState();
          };

          scope.popupContinue = function () {
            if (!scope.popup.active || !scope.popup.canContinue) {
              return;
            }
            if (window.bngApi && bngApi.engineLua) {
              bngApi.engineLua("extensions.bolidesTheCut._popupContinue()");
            }
          };

          scope.preloadRobber = function () {
            if (scope.hudTrial.preloaded || !scope.hudTrial.preloadAvailable) {
              return;
            }
            if (window.bngApi && bngApi.engineLua) {
              bngApi.engineLua("extensions.bolidesTheCut.preloadRobberFromHud()");
            }
          };

          scope.toggleAbout = function () {
            if (window.bngApi && bngApi.engineLua) {
              bngApi.engineLua("extensions.bolidesTheCut.toggleHudAbout()");
            }
          };

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
