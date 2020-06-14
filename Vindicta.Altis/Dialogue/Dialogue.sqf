#include "common.hpp"

/*
Dialogue class.
Manages a conversation between two characters, one of which is player.
*/

#define OOP_CLASS_NAME Dialogue
CLASS("Dialogue", "")

	// Array of nodes
	VARIABLE("nodes");

	// Remote client ID of the user doing the dialogue
	VARIABLE("remoteClientID");

	// Time when this was updated last time
	VARIABLE("timeLastProcess");

	// Time when the current sentence will be over
	VARIABLE("timeSentenceEnd");

	// State of execution of current node
	VARIABLE("state");

	// Current node ID to execute
	VARIABLE("nodeID");

	// Stack of node IDs (analog of address), like computer's stack memory
	VARIABLE("callStack");

	// Flag, true when we are handling an event. It's needed so that we don't handle another
	// event while handling this one
	VARIABLE("handlingEvent");

	// Object handles - units performing the dialogue
	VARIABLE("unit0"); // Always AI
	VARIABLE("unit1"); // AI or player

	METHOD(new)
		params [P_THISOBJECT, P_ARRAY("_nodes"), P_OBJECT("_unit0"),
					P_OBJECT("_unit1"), P_NUMBER("_clientID")];

		T_SETV("nodes", _nodes);
		T_SETV("remoteClientID", _clientID);
		T_SETV("unit0", _unit0);
		T_SETV("unit1", _unit1);

		T_SETV("nodeID", 0);
		T_SETV("callStack", []);
		T_SETV("timeLastProcess", -1); // Means it wasn't updated yet
		T_SETV("timeSentenceEnd", 0);
		T_SETV("handlingEvent", false);
	ENDMETHOD;

	METHOD(delete)
		params [P_THISOBJECT];

		T_CALLM0("terminate");
		// todo send message to client
	ENDMETHOD;

	// Must be called periodically, up to once per frame
	METHOD(process)
		params [P_THISOBJECT];

		// Bail if dialogue is over
		pr _state = T_GETV("state");
		if (_state == DIALOGUE_STATE_END) exitWith {};

		// Calculate delta-time
		pr _timeLastProcess = T_GETV("timeLastProcess");
		pr _deltaTime = if (_timeLastProcess < 0) then {0} else {
			time - _timeLastProcess;
		};

		// Check if units walked away or died
		pr _unit0 = T_GETV("unit0");
		pr _unit1 = T_GETV("unit1");

		if (!T_GETV("handlingEvent")) then {
			// Check if someone is not alive of null
			if (!(alive _unit0) || !(alive _uni1)) then {
				T_CALLM1("_handleCriticalEvent", NODE_TAG_EVENT_NOT_ALIVE);
			} else {
				// Check if units are far away
				if ((_unit0 distance _unit1) > DIALOGUE_DISTANCE) then {
					T_CALLM1("_handleCriticalEvent", NODE_TAG_EVENT_AWAY);
				};
			};
		};

		// Check current node
		pr _nodes = T_GETV("nodes");
		pr _nodeID = T_GETV("nodeID");

		// Bail if we have reached the end of the node array
		if (_nodeID >= (count _nodes) || _nodeID < 0) exitWith {
			T_SETV("state", DIALOGUE_STATE_END);
		};

		pr _error = false; // Error flag, set it if an error has happened
		pr _node = _nodes#_nodeID;
		pr _type = _node#NODE_ID_TYPE;
		pr _tag = _node#NODE_ID_TAG;

		// Select the rest of the array (omit type and tag)
		pr _nodeTail = _node select [2, 100];

		switch (_type) do {

			// Show sentence
			case NODE_TYPE_OPTION;
			case NODE_TYPE_SENTENCE: {
				T_CALLM1("nodeSentence", _nodeTail);
				_nodeTail params [P_NUMBER("_talker"), P_STRING("_text")];

				switch (_state) do {
					// Start this sentence
					case DIALOGUE_STATE_RUN: {
						// todo link with UI


						// Start lip animation
						pr _talkObject = T_GETV("unit0");
						if (_talker == TALKER_1) then {
							_talkObject = T_GETV("unit1");
						};
						[_talkObject, true] remoteExecCall ["setRandomLip", 0];

						// Calculate time when the sentence ends
						pr _duration = SENTENCE_DURATION(_text);
						pr _timeEnd = time + _duration;
						T_SETV("timeSentenceEnd", _timeEnd);

						// Set state
						T_SETV("state", DIALOGUE_STATE_WAIT_SENTENCE_END);
					};

					// Wait until this sentence is over
					case DIALOGUE_STATE_WAIT_SENTENCE_END: {
						if (time > T_GETV("timeSensenceEnd")) then {
							// Stop lip animation
							[T_GETV("unit0"), false] remoteExecCall ["setRandomLip", 0];
							[T_GETV("unit1"), false] remoteExecCall ["setRandomLip", 0];

							// Set state
							T_SETV("state", DIALOGUE_STATE_RUN);

							// Go to next node
							T_SETV("nodeID", _nodeID + 1);
						} else {
							// Wait for this sentence to end...
						};
					};

					default {
						OOP_ERROR_2("Invalid state: %1, node: %2", _state, _node);
						_error = true;
					};
				};
			};

			// Go to another node
			case NODE_TYPE_JUMP_IF;
			case NODE_TYPE_JUMP: {
				_nodeTail params [P_STRING("_tagNext"), P_STRING("_methodName"), P_ARRAY("_arguments")];
				if (_state != DIALOGUE_STATE_RUN) then {
					OOP_ERROR_2("Invalid state: %1, node: %2", _state, _node);
					_error = true;					
				} else {
					pr _do = true;

					// If it's an 'if' node, also call method to evaluate the statement
					if (_methodName != "") then {
						pr _callResult = CALLM(_thisObject, _methodName, _arguments);
						if (!_callResult) then { _do = false; };
					};

					if (_do) then {
						pr _stack = T_GETV("callStack");
						T_CALLM1("goto", _tagNext);
					};
				};
			};

			// Go to another node and push address of next node to stack
			// So we can return from that sequence later
			case NODE_TYPE_CALL_IF;
			case NODE_TYPE_CALL: {
				_nodeTail params [P_STRING("_tagCall"), P_STRING("_methodName"), P_ARRAY("_arguments")];
				if (_state != DIALOGUE_STATE_RUN) then {
					OOP_ERROR_2("Invalid state: %1, node: %2", _state, _node);
					_error = true;					
				} else {
					pr _do = true;

					// If it's an 'if' node, also call method to evaluate the statement
					if (_methodName != "") then {
						pr _callResult = CALLM(_thisObject, _methodName, _arguments);
						if (!_callResult) then { _do = false; };
					};

					if (_do) then {
						pr _stack = T_GETV("callStack");
						_stack pushBack (_nodeID+1); // We will return to next node
						T_CALLM1("goto", _tagNext);
					};
				};
			};

			// Return from sequence to address stored in stack
			// Only makes sense after a call
			case NODE_TYPE_RETURN: {
				if (_state != DIALOGUE_STATE_RUN) then {
					OOP_ERROR_2("Invalid state: %1, node: %2", _state, _node);
					_error = true;					
				} else {
					pr _stack = T_GETV("callStack");
					if (count _stack == 0) then {
						// If there is nothing else in the stack then we should end the dialogue
						T_SETV("state", DIALOGUE_STATE_END);
					} else {
						// Pop node tag from the stack and go there
						pr _idReturn = _stack deleteAt ((count _stack) - 1);
						T_SETV("nodeID", _idReturn);
					};
				};
			};


			// Show options to client
			case NODE_TYPE_OPTIONS: {
				_nodeTail params [P_ARRAY("_optionsArray")];

				switch (_state) do {

					// Make an array of data to send to client
					case DIALOGUE_STATE_RUN: {
						// It will contain the text of each option and tag
						pr _clientData = [];
						pr _error = false;
						{
							pr _nodeID = T_CALLM1("findNode", _x);
							pr _nodeOpt = _nodes#_nodeID;
							if (_nodeOpt#NODE_ID_TYPE != NODE_TYPE_OPTION) then {
								OOP_ERROR_1("Node %1 has wrong type, expected OPTION", _nodeID);
								_error = true;
							} else {
								_clientData pushBack [_x, _nodeOpt#3];
							};
						} forEach _optionsArray;

						if (count _clientData > 0 && !_error) then {
							// Send data to client

							// todo

							// Now we are waiting for client's response
							T_SETV("state", DIALOGUE_STATE_WAIT_OPTION);
						} else {
							// Raise error
							OOP_ERROR_1("Could not find option nodes for tag %1", _tag);
							_error = true;
						};
					};

					// We are still waiting for user to choose the option
					// Do nothing
					case DIALOGUE_STATE_WAIT_OPTION: {
						
					};

					default {
						OOP_ERROR_2("Invalid state: %1, node: %2", _state, _node);
						_error = true;
					};
				};
			};

			// Call code and continue
			case NODE_TYPE_CALL_METHOD: {
				_nodeTail params [P_STRING("_method"), P_ARRAY("_arguments")];

				if (_state != DIALOGUE_STATE_RUN) then {
					OOP_ERROR_2("Invalid state: %1, node: %2", _state, _node);
					_error = true;					
				} else {
					// Call method
					CALLM(_thisObject, _method, _arguments);
					// Go to next node
					T_SETV("nodeID", _nodeID + 1);
				};
			};


			default {
				OOP_ERROR_1("Unknown node type: %1", _type);
			};
		};

		// Find out what to do now
		if (_error) then {
			T_SETV("state", DIALOGUE_STATE_END);
		};

	ENDMETHOD;

	// Finds node and prints error if node was not found
	METHOD(findNode)
		params [P_THISOBJECT, P_STRING("_tag")];
		pr _id = FIND_NODE(T_GETV("nodes"), _tag);
		if (_id == -1) then {
			OOP_ERROR_1("Could not find node with tag %1", _tag);
		};
		_id;
	ENDMETHOD;

	// Sets current node to a node with given tag
	METHOD(goto)
		params [P_THISOBJECT, P_STRING("_tag")];
		pr _id = T_CALLM1("findNode", _tag);
		T_SETV("nodeID", _id);
		T_SETV("state", DIALOGUE_STATE_RUN);
	ENDMETHOD;

	// Handles a critical event - that is event which can lead to termination
	// of the dialogue.
	// It tries to jump to an event handler node if it's found, otherwise it ends the dialogue
	METHOD(_handleCriticalEvent)
		params [P_THISOBJECT, P_STRING("_tag")];
		pr _nodes = T_GETV("nodes");
		pr _nodeID = FIND_NODE(_nodes, _tag);
		if (_nodeID == -1) then {
			// Just terminate this
			T_SETV("state", DIALOGUE_STATE_END);
		} else {
			// Jump to that node
			T_SETV("nodeID", _nodeID);
			T_SETV("handlingEvent", true);
		};
	ENDMETHOD;

	// Called before dialogue is deleted
	METHOD(terminate)
		params [P_THISOBJECT];
		// Force-stop lip animations
		[T_GETV("unit0"), false] remoteExecCall ["setRandomLip", 0];
		[T_GETV("unit1"), false] remoteExecCall ["setRandomLip", 0];
		// Send data to client
		// todo
	ENDMETHOD;

	// Returns true if the dialogue has ended, because of any reason
	// (someone walked away or died or it just ended naturally)
	METHOD(hasEnded)
		params [P_THISOBJECT];
		T_GETV("state") == DIALOGUE_STATE_END;
	ENDMETHOD;

ENDCLASS;