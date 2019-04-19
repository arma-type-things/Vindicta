#define OOP_DEBUG
#define OOP_INFO
#define OOP_WARNING
#define OOP_ERROR
// #define OOP_PROFILE

#include "common.hpp"

#define REINF_MAX_DIST 4000

// Commander planning AI
CLASS("CmdrAI", "")
	VARIABLE("side");
	VARIABLE("activeActions");

	METHOD("new") {
		params [P_THISOBJECT, P_SIDE("_side")];
		T_SETV("side", _side);
		T_SETV("activeActions", []);
	} ENDMETHOD;

	// METHOD("isValidAttackTarget") {
	// 	params [P_THISOBJECT, P_STRING("_garrison")];
	// 	T_PRVAR(side);
	// 	!CALLM0(_garrison, "isDead") and CALLM0(_garrison, "getSide") != _side
	// } ENDMETHOD;

	// METHOD("isValidAttackSource") {
	// 	params [P_THISOBJECT, P_STRING("_garrison")];
	// 	T_PRVAR(side);
	// 	!CALLM0(_garrison, "isDead") and CALLM0(_garrison, "getSide") == _side
	// } ENDMETHOD;

	// METHOD("isValidTakeOutpostTarget") {
	// 	params [P_THISOBJECT, P_STRING("_location")];
	// 	T_PRVAR(side);
	// 	CALLM0(_location, "getSide") != _side
	// } ENDMETHOD;
	
	// fn_isValidAttackTarget = {
	// 	!CALLM0(_this, "isDead") and CALLM0(_this, "getSide") != _side
	// };

	// fn_isValidAttackSource = {
	// 	!CALLM0(_this, "isDead") and CALLM0(_this, "getSide") == _side
	// };

	// fn_isValidOutpostTarget = {
	// 	CALLM0(_this, "getSide") != _side
	// };

	METHOD("generateTakeOutpostActions") {
		params [P_THISOBJECT, P_STRING("_world")];
		T_PRVAR(activeActions);
		T_PRVAR(side);

		// // Garrison must be alive
		// // TODO: optimize this into a single garrison function maybe?
		// private _garrisons = CALLM(_world, "getAliveGarrisons", []) select { 
		// 	// Must be on our side
		// 	( GETV(_x, "side") == _side ) and 
		// 	// Must have at least a minimum strength
		// 	{ !CALLM(_x, "isDepleted", []) } and 
		// 	// Must not be engaged in another action
		// 	{ !CALLM(_x, "isBusy", []) }
		// };

		// private _locations = GETV(_world, "locations") select {
		// 	private _location = _x;
		// 	// Only try to take empty or enemy locations
		// 	GETV(_location, "side") != _side and
		// 	// Don't make duplicate take actions for the same location
		// 	_activeActions findIf { 
		// 		OBJECT_PARENT_CLASS_STR(_x) == "TakeOutpostCmdrAction" and 
		// 		{ GETV(_x, "targetOutpostId") == GETV(_location, "id") }
		// 	} == NOT_FOUND
		// };

		private _actions = [];
		// {
		// 	private _garrisonId = GETV(_x, "id");
		// 	{
		// 		private _locationId = GETV(_x, "id");
		// 		private _params = [_garrisonId, GETV(_x, "id")];
		// 		_actions pushBack NEW("TakeOutpostCmdrAction", _params);
		// 	} forEach _locations;
		// } forEach _garrisons;

		_actions
	} ENDMETHOD;

	METHOD("generateAttackActions") {
		params [P_THISOBJECT, P_STRING("_world")];

		private _garrisons = GETV(_world, "garrisons");

		T_PRVAR(side);

		private _actions = [];

		// for "_i" from 0 to count _garrisons - 1 do {
		// 	private _enemyGarr = _garrisons select _i;
		// 	if(_enemyGarr call fn_isValidAttackTarget) then {
		// 		for "_j" from 0 to count _garrisons - 1 do {
		// 			private _ourGarr = _garrisons select _j;
		// 			if((_ourGarr call fn_isValidAttackSource) and (CALLM0(_ourGarr, "getStrength") > CALLM0(_enemyGarr, "getStrength"))) then {
		// 				private _params = [_j, _i];
		// 				_actions pushBack (NEW("AttackAction", _params));
		// 			};
		// 		};
		// 	};
		// };

		_actions
	} ENDMETHOD;

	// fn_isValidReinfGarr = {
	// 	if(CALLM0(_this, "isDead") or (CALLM0(_this, "getSide") != _side)) exitWith { false };
	// 	private _action = GETV(_this, "currAction");
	// 	if(!(_action isEqualType "")) exitWith { true };

	// 	OBJECT_PARENT_CLASS_STR(_action) != "ReinforceAction"
	// };

	METHOD("generateReinforceActions") {
		params [P_THISOBJECT, P_STRING("_world")];
		T_PRVAR(side);

		private _garrisons = CALLM(_world, "getAliveGarrisons", []) select { 
			// Must be on our side
			GETV(_x, "side") == _side and 
			// Not involved in another reinforce action
			{
				private _action = CALLM(_x, "getAction", []);
				IS_NULL_OBJECT(_action) or { OBJECT_PARENT_CLASS_STR(_action) != "ReinforceCmdrAction" }
			}
		};

		T_PRVAR(side);

		// Source garrisons must have a minimum eff
		private _srcGarrisons = _garrisons select { 
			// Must have at least a minimum strength of twice min efficiency
			private _eff = GETV(_x, "efficiency");
			EFF_GTE(_eff, EFF_MUL_SCALAR(EFF_MIN_EFF, 2)) and 
			// !CALLM(_x, "isDepleted", []) and 
			// Not involved in another action already
			{ !CALLM(_x, "isBusy", []) }
		};

		private _tgtGarrisons = _garrisons select { 
			// Must have at least a minimum strength of twice min efficiency
			private _eff = GETV(_x, "efficiency");
			private _overDesiredEff = CALLM(_world, "getOverDesiredEff", [_x]);
			!EFF_GT(_overDesiredEff, EFF_ZERO)
		};

		private _actions = [];
		{
			private _srcGarrison = _x;
			private _srcPos = GETV(_srcGarrison, "pos");
			{
				private _tgtGarrison = _x;
				private _tgtPos = GETV(_tgtGarrison, "pos");
				if(_srcGarrison != _tgtGarrison 
					// and {_srcPos distance _tgtPos < REINF_MAX_DIST}
					) then {
					private _params = [GETV(_srcGarrison, "id"), GETV(_tgtGarrison, "id")];
					_actions pushBack (NEW("ReinforceCmdrAction", _params));
				};
			} forEach _tgtGarrisons;
		} forEach _srcGarrisons;

		_actions
	} ENDMETHOD;

	METHOD("generateRoadblockActions") {
		params [P_THISOBJECT, P_STRING("_world")];

		private _garrisons = GETV(_world, "garrisons");

		T_PRVAR(side);
		private _actions = [];

		// TODO: generate roadblock actions

		_actions
	} ENDMETHOD;

	METHOD("update") {
		params [P_THISOBJECT, P_STRING("_world")];

		//T_PRVAR(world);
		T_PRVAR(activeActions);

		OOP_DEBUG_MSG("[c %1 w %2] - - - - - U P D A T I N G - - - - -   on %3 active actions", [_thisObject]+[_world]+[count _activeActions]);

		// Update actions in real world
		{ CALLM(_x, "update", [_world]) } forEach _activeActions;

		// Remove complete actions
		private _completeActions = _activeActions select { CALLM(_x, "isComplete", []) };

		// Unref completed actions
		{
			UNREF(_x);
		} forEach _completeActions;

		_activeActions = _activeActions - _completeActions;

		T_SETV("activeActions", _activeActions);

		OOP_DEBUG_MSG("[c %1 w %2] - - - - - U P D A T I N G   D O N E - - - - -", [_thisObject]+[_world]);
	} ENDMETHOD;

	METHOD("plan") {
		params [P_THISOBJECT, P_STRING("_world")];

		OOP_DEBUG_MSG("[c %1 w %2] - - - - - P L A N N I N G - - - - -", [_thisObject]+[_world]);

		//T_PRVAR(world);
		T_PRVAR(activeActions);

		OOP_DEBUG_MSG("[c %1 w %2] Creating new simworld from %2", [_thisObject]+[_world]);

		// Copy world to simworld
		private _simWorld = CALLM(_world, "simCopy", []);

		OOP_DEBUG_MSG("[c %1 w %2] Applying %3 active actions to simworld", [_thisObject]+[_world]+[count _activeActions]);

		PROFILE_SCOPE_START(ApplyActive);
		// Apply effects of active actions to the simworld
		{
			CALLM(_x, "applyToSim", [_simWorld]);
		} forEach _activeActions;
		PROFILE_SCOPE_END(ApplyActive, 0.1);

		OOP_DEBUG_MSG("[c %1 w %2] Generating new actions", [_thisObject]+[_world]);

		PROFILE_SCOPE_START(GenerateActions);
		// Generate possible new actions based on the simworld
		// (i.e. taking into account expected outcomes of currently active actions)
		private _newActions = 
			  T_CALLM("generateTakeOutpostActions", [_simWorld])
			// TODO: general attack actions (QRF)
			//+ T_CALLM1("generateAttackActions", _simWorld) 
			+ T_CALLM("generateReinforceActions", [_simWorld]) 
			// TODO: roadblocks/outposts etc. Maybe this is up to garrison AI itself?
			//+ T_CALLM1("generateRoadblockActions", _simWorld)
			;
		PROFILE_SCOPE_END(GenerateActions, 0.1);

		OOP_DEBUG_MSG("[c %1 w %2] Generated %3 new actions, updating plan", [_thisObject]+[_world]+[count _newActions]);

		PROFILE_SCOPE_START(PlanActions);

		private _newActionsCount = 0;
		// Plan new actions
		while { count _newActions > 0 and _newActionsCount < 5 } do {
			OOP_DEBUG_MSG("[c %1 w %2]     Updating scoring for %3 remaining new actions", [_thisObject]+[_world]+[count _newActions]);

			CALLM(_world, "resetScoringCache", []);

			PROFILE_SCOPE_START(UpdateScores);
			// Update scores of potential actions against the simworld state
			{
				CALLM1(_x, "updateScore", _simWorld);
			} forEach _newActions;
			PROFILE_SCOPE_END(UpdateScores, 0.1);

			// Sort the actions by their scores
			private _scoresAndActions = _newActions apply { [CALLM(_x, "getFinalScore", []), _x] };
			_scoresAndActions sort DESCENDING;

			// _newActions = [_newActions, [], { CALLM(_x, "getFinalScore", []) }, "DECEND"] call BIS_fnc_sortBy;

			// Get the best scoring action
			(_scoresAndActions deleteAt 0) params ["_bestActionScore", "_bestAction"];
			// private _bestActionScore = // CALLM(_bestAction, "getFinalScore", []);

			// Some sort of cut off needed here, probably needs tweaking, or should be strategy based?
			if(_bestActionScore <= 0.001) exitWith {
				OOP_DEBUG_MSG("[c %1 w %2]     Best new action %3 (score %4), score below threshold of 0.001, terminating planning", [_thisObject]+[_world]+[_bestAction]+[_bestActionScore]);
			};

			OOP_DEBUG_MSG("[c %1 w %2]     Selected new action %3 (score %4), applying it to the sim", [_thisObject]+[_world]+[_bestAction]+[_bestActionScore]);

			// Add the best action to our active actions list
			REF(_bestAction);
			_activeActions pushBack _bestAction;

			PROFILE_SCOPE_START(ApplyNewActionToSim);
			// Apply the new action effects to simworld, so next loop scores update appropriately
			// (e.g. if we just accepted a new reinforce action, we should update the source and target garrison
			// models in the sim so that other reinforce actions will take it into account in their scoring.
			// Probably other reinforce actions with the same source or target would have lower scores now).
			CALLM(_bestAction, "applyToSim", [_simWorld]);
			PROFILE_SCOPE_END(ApplyNewActionToSim, 0.1);
		};
		PROFILE_SCOPE_END(PlanActions, 0.1);

		OOP_DEBUG_MSG("[c %1 w %2] Done updating plan, added %3 new actions, cleaning up %4 unused new actions", [_thisObject]+[_world]+[_newActionsCount]+[count _newActions]);

		// Delete any remaining discarded actions
		{
			DELETE(_x);
		} forEach _newActions;

		OOP_DEBUG_MSG("[c %1 w %2] - - - - - P L A N N I N G   D O N E - - - - -", [_thisObject]+[_world]);
	} ENDMETHOD;

ENDCLASS;
