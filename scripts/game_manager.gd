extends Node

signal monedas_actualizadas(valor: int)

var selected_test_id: int = 0
var selected_test_title: String = ""
var ordered_test_ids: Array[int] = []

var monedas: int = 0

func set_monedas(valor: int) -> void:
	monedas = maxi(0, valor)
	monedas_actualizadas.emit(monedas)

func next_test_id() -> int:
	var i := ordered_test_ids.find(selected_test_id)
	if i == -1 or i + 1 >= ordered_test_ids.size():
		return 0
	return ordered_test_ids[i + 1]
