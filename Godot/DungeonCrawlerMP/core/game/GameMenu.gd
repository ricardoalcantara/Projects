extends Control

const LoadGameDialogScn      = preload("res://core/gui/LoadGameDialog.tscn")
const SaveGameDialogScn      = preload("res://core/gui/SaveGameDialog.tscn")
const LiveGameLobbyScn       = preload("res://core/gui/lobby/LiveGameLobby.tscn")
const GameSceneGd            = preload("./GameScene.gd")

var m_game : GameSceneGd               setget setGame


signal resumed
signal lobbyAdded
signal fileSelected
signal quitRequested


func _ready():
	var isClient =  get_tree().has_network_peer() and not is_network_master()
	$"Buttons/Save".set_disabled( isClient )
	$"Buttons/Load".set_disabled( isClient )


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		pass


func onResumePressed():
	emit_signal("resumed")


func onQuitPressed():
	emit_signal("quitRequested")


func onSavePressed():
	if get_tree().has_network_peer() and not is_network_master():
		return

	var dialog = SaveGameDialogScn.instance()
	assert( not has_node( dialog.get_name() ) )
	dialog.connect("file_selected", m_game, "saveGame")
	dialog.connect("file_selected", self, "onFileSelected")
	self.add_child(dialog)
	dialog.popup()
	dialog.connect("hide", dialog, "queue_free")


func onLoadPressed():
	if get_tree().has_network_peer() and not is_network_master():
		return

	var dialog = LoadGameDialogScn.instance()
	assert( not has_node( dialog.get_name() ) )
	dialog.connect("file_selected", m_game, "loadGame")
	dialog.connect("file_selected", self, "onFileSelected")
	self.add_child(dialog)
	dialog.popup()
	dialog.connect("hide", dialog, "queue_free")


func onFileSelected( fileName ):
	emit_signal( "fileSelected" )


func onLobbyPressed():
	var lobby = LiveGameLobbyScn.instance()
	m_game.add_child( lobby )
	emit_signal("lobbyAdded")


func setGame( game ):
	m_game = game
