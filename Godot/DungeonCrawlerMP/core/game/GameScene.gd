extends Node

const GameCreatorGd          = preload("./GameCreator.gd")
const GameCreatorServerGd    = preload("./GameCreatorServer.gd")
const GameCreatorClientGd    = preload("./GameCreatorClient.gd")
const LevelBaseGd            = preload("res://core/level/LevelBase.gd")
const SavingModuleGd         = preload("res://core/SavingModule.gd")
const SerializerGd           = preload("res://core/Serializer.gd")
const UtilityGd              = preload("res://core/Utility.gd")

const GameCreatorName        = "GameCreator"

enum Params { Module, PlayerUnitsData, PlayerIds }
enum State { Initial, Creating, Running, Finished }

var m_module : SavingModuleGd          setget deleted # setCurrentModule
var m_currentLevel : LevelBaseGd       setget deleted # setCurrentLevel
var m_rpcTargets : Array = []          # _setRpcTargets
var m_state : int = State.Initial      setget deleted # _changeState
var m_clientsAwaitingState : Array = []setget deleted

onready var m_creator : GameCreatorGd     = $"GameCreator"
onready var m_playerManager               = $"PlayerManager"   setget deleted
onready var m_currentLevelParent          = $"GameWorldView/Viewport"


signal gameStarted()
signal gameFinished()
signal readyCompleted()
signal playerReady( id )


func deleted(_a):
	assert(false)


func _enter_tree():
	OS.delay_msec( int(Debug.m_gameSceneDelay * 1000) )
	Network.connect("clientListChanged", self, "_adjustToClients")


func _ready():
	if Network.isServer():
		m_creator.set_script( GameCreatorServerGd )

	m_creator.setGame( self )

	var params = SceneSwitcher.getParams()
	if params == null:
		return

	if params.has( Params.PlayerIds ) and Network.isServer():
		m_playerManager.setPlayerIds( params[Params.PlayerIds] )
		Debug.info( self, "GameScene: Players set " + str( m_playerManager.getPlayerIds() ) )

	var module : SavingModuleGd = null
	if params.has( Params.Module ) and params[Params.Module] != null:
		module = params[Params.Module]
	elif is_network_master():
		Debug.info(self, "GameScene: no module on network master")

	if is_network_master() and module != null:
		call_deferred( "createGame", module )

	if params.has( Params.PlayerUnitsData ) and is_network_master():
		m_creator.setPlayerUnitsCreationData( params[Params.PlayerUnitsData] )

	if Network.isServer():
		Network.connect("nodeRegisteredClientsChanged", self, "_onNodeRegisteredClientsChanged")

	if is_network_master() == false:
		Network.RPCmaster( self, ["onClientReady"] )

	emit_signal( "readyCompleted" )


func _exit_tree():
	if Network.isClient():
		Network.RPCmaster( Network, ["unregisterNodeForClient", get_path()] )


func createGame( module ):
	m_creator.call_deferred( "prepare" )
	var result = yield( m_creator, "prepareFinished" )

	if result != OK:
		Debug.err(self, "GameScene: could not prepare game")
		finish()
		return

	Network.RPC( self, ["createGameOnClient"] )
	_changeState( State.Creating )

	OS.delay_msec( int(Debug.m_createGameDelay * 1000) )

	m_creator.call_deferred( "createFromModule", module )
	result = yield( m_creator, "createFinished" )

	if result != OK:
		Debug.err(self, "GameScene: could not create game")
		finish()
		return

	start()


puppet func createGameOnClient():
	_changeState( State.Creating )
	var err = yield( m_creator, "createFinished" )
	if err == OK:
		start()


func saveGame( filepath : String ):
	assert( m_state in [State.Running] )
	var revertPaused = UtilityGd.scopeExit( self, "setPaused", [get_tree().paused] )
	setPaused( true )
	m_module.saveLevel( m_currentLevel )
	m_module.savePlayerUnits( UtilityGd.toPaths( getPlayerUnits() ) )
	return m_module.saveToFile( filepath )


func loadGame( filepath : String ):
	assert( is_network_master() )
	assert( m_state in [State.Running, State.Initial] )
	var previousState = m_state
	_changeState( State.Creating )

	Network.RPC( self, ["loadGameOnClient"] )
	var result = yield( m_creator.createFromFile( filepath ), "completed" )

	start() if result == OK else _changeState( previousState )


puppet func loadGameOnClient():
	_changeState( State.Creating )
	var err = yield( m_creator, "createFinished" )
	if err == OK:
		start()


func loadLevel( levelName : String ) -> int:
	_changeState( State.Creating )
	var result = yield( m_creator.loadLevel( levelName ), "completed" )
	_changeState( State.Running )
	return result


func unloadCurrentLevel() -> int:
	_changeState( State.Creating )
	var result = yield( m_creator.unloadCurrentLevel(), "completed" )
	_changeState( State.Running )
	return result


master func onClientReady():
	var clientId = get_tree().get_rpc_sender_id()
	match m_state:
		State.Initial:
			Network.RPCid( self, clientId, ["receiveGameState", m_state, []] )
		State.Running:
			var serializedLevel = SerializerGd.serialize( m_currentLevel )
			Network.RPCid( self, clientId,
				["receiveGameState", m_state, serializedLevel] )
		State.Creating:
			m_clientsAwaitingState.append( clientId )


puppet func receiveGameState( state : int, serializedLevel : Array ):
	assert( not is_network_master() )
	match( state ):
		State.Initial:
			Network.RPCmaster( Network, ["registerNodeForClient", get_path()] )
		State.Running:
			var revertState = UtilityGd.scopeExit( self, "_changeState", [State.Running] )
			_changeState( State.Creating )
			SerializerGd.deserialize( serializedLevel, m_currentLevelParent )
			setCurrentLevel( m_currentLevelParent.get_node(serializedLevel[0]) )
			Network.RPCmaster( Network, ["registerNodeForClient", get_path()] )


func start():
	_changeState( State.Running )
	print( "-----\nGAME START\n-----" )
	emit_signal("gameStarted")


puppet func finish():
	if is_network_master():
		Network.RPC( self, ["finish"] )

	_changeState( State.Finished )


func setPaused( enabled : bool ):
	get_tree().paused = enabled
	Debug.updateVariable( "Pause", "Yes" if get_tree().paused else "No" )


func setCurrentLevel( level : LevelBaseGd ):
	assert( level == null or m_currentLevelParent.is_a_parent_of( level ) )
	m_currentLevel = level


func setCurrentModule( module : SavingModuleGd ):
	assert( m_state == State.Creating )
	assert( module != m_module )
	assert( m_currentLevel == null )
	m_playerManager.setPlayerUnits( [] )
	m_module = module


func getPlayerUnits():
	return m_playerManager.getPlayerUnitNodes()


func onNodeRegisteredClientsChanged( nodePath : NodePath, nodesWithClients ):
	if nodePath == get_path():
		_setRpcTargets( nodesWithClients[nodePath] )


func _adjustToClients( clients : Dictionary ):
	var newRpcTargets : Array = []
	for target in m_rpcTargets:
		if target in clients.keys():
			newRpcTargets.append( target )

	if newRpcTargets != m_rpcTargets:
		_setRpcTargets( newRpcTargets )


func _changeState( state : int ):
	assert( m_state != State.Finished )

	if state == m_state:
		Debug.warn(self, "changing to same state")
		return

	if state == State.Finished:
		call_deferred( "emit_signal", "gameFinished" )

	elif state == State.Running:
		if not m_clientsAwaitingState.empty():
			var serializedLevel = SerializerGd.serialize( m_currentLevel )
			for clientId in m_clientsAwaitingState:
				Network.RPCid( self, clientId, ["receiveGameState", state, serializedLevel] )
			m_clientsAwaitingState.clear()
		setPaused(false)

	elif state == State.Creating:
		setPaused(true)

	m_state = state


func _onNodeRegisteredClientsChanged( nodePath : NodePath, nodesWithClients ):
	if nodePath != get_path():
		return

	var clients : Array = nodesWithClients[nodePath]
	var newPlayers : Array = []
	var targetsToSet : Array = []
	for clientId in clients:
		targetsToSet.append( clientId )
		if not clientId in m_rpcTargets:
			newPlayers.append( clientId )

	_setRpcTargets( targetsToSet )
	for playerId in newPlayers:
		emit_signal( "playerReady", playerId )


func _setRpcTargets( clientIds : Array ):
	assert( Network.isServer() )
	assert( not Network.ServerId in clientIds )
	Network.setRpcTargets( self, clientIds )
	m_playerManager.m_rpcTargets = m_rpcTargets
	m_creator.m_rpcTargets = m_rpcTargets
