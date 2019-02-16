extends Node

var m_consumeInput = true              setget setConsumingInput

var m_sequences = {}                   setget deleted
var m_actions = []                     setget deleted
var m_allActions = []                  setget deleted

var m_possibleSequences = []           setget deleted
var m_positionInSequence = 0           setget deleted

onready var m_timer  = $"Timer"


signal sequenceDetected( id )


func deleted(_a):
	assert(false)


func _enter_tree():
	useInput()


func _input( event ):
	_handleEvent( event )


func reset():
	m_possibleSequences = m_sequences.keys()
	m_positionInSequence = 0


func useInput():
	set_process_input( true )
	set_process_unhandled_input( false )


func useUnhandledInput():
	set_process_input( false )
	set_process_unhandled_input( true )


# idToSequence is dict of int : array of Strings
func addSequences( idToSequence ):
	var discardedIdToMessage  = {}
	for id in idToSequence:
		var sequence = idToSequence[id]
		var isError = false

		if sequence.size() == 0:
			discardedIdToMessage[id] = "Input sequence is empty"
			isError = true

		if m_sequences.has( id ):
			discardedIdToMessage[id] = "Sequence ID already exists"
			isError = true

		for seq in m_sequences.values():
			if seq == sequence:
				discardedIdToMessage[id] = "Sequence already exists"
				isError = true
				break

		if not isError:
			m_sequences[id] = sequence

	_updateAllActions()
	reset()
	return discardedIdToMessage


func removeSequences( ids ):
	for id in ids:
		m_sequences.erase( id )
	_updateAllActions()
	reset()


# adds action that is not neccesarily part of any sequence
# those actions will be able to fail a sequence
func addActions( actions ):
	for action in actions:
		if not m_actions.has( action ):
			m_actions.push_back( action )
	_updateAllActions()


func removeActions( actions ):
	for action in actions:
		m_actions.remove( m_actions.find( action ) )
	_updateAllActions()


func setConsumingInput( consume ):
	m_consumeInput = consume


func _updateAllActions():
	var allActions = []
	for sequence in m_sequences.values():
		for action in sequence:
			if not allActions.has( action ):
				allActions.append( action )

	for action in m_actions:
		if not allActions.has( action ):
			allActions.append( action )

	m_allActions = allActions


func _handleEvent( event ):
	var eventAction = ""
	for action in m_allActions:
		if event.is_action_pressed(action):
			eventAction = action
			break

	if not eventAction.empty():
		_validateSequence( eventAction )
		if m_consumeInput:
			get_tree().set_input_as_handled()


func _validateSequence( action ):
	var newPossibleSequences = []

	for seqId in m_possibleSequences:
		if m_sequences[seqId][m_positionInSequence] == action:
			if m_sequences[seqId].size() == m_positionInSequence + 1:
				emit_signal( "sequenceDetected", seqId )
			else:
				 newPossibleSequences.append(seqId)

	if newPossibleSequences.empty():
		reset()
	else:
		m_timer.start( )
		m_possibleSequences = newPossibleSequences
		m_positionInSequence += 1
