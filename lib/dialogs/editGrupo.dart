import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:money_facil/ip.dart';
import 'package:money_facil/screens/login.dart';
import 'package:shared_preferences/shared_preferences.dart';

class editGrupoDialog extends StatefulWidget {
  final VoidCallback onGrupoEditado;
  final String idGrupo; // Nuevo parámetro para recibir el idGrupo

  editGrupoDialog({required this.onGrupoEditado, required this.idGrupo});

  @override
  _editGrupoDialogState createState() => _editGrupoDialogState();
}

class _editGrupoDialogState extends State<editGrupoDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController nombreGrupoController = TextEditingController();
  final TextEditingController descripcionController = TextEditingController();
  final TextEditingController liderGrupoController = TextEditingController();
  final TextEditingController miembrosController = TextEditingController();

  final List<Map<String, dynamic>> _selectedPersons = [];
  final TextEditingController _controller = TextEditingController();

  Map<String, String> _originalCargos = {};

  List<String> _clientesEliminados =
      []; // Lista para almacenar los IDs de los clientes eliminados

  String? selectedTipo;

  List<String> tiposGrupo = [
    'Grupal',
    'Individual',
    'Selecto',
  ];

  List<String> cargos = ['Miembro', 'Presidente/a', 'Tesorero/a'];

  // Agregamos un mapa para guardar el rol de cada persona seleccionada
  Map<String, String> _cargosSeleccionados = {};

  late TabController _tabController;
  int _currentIndex = 0;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _infoGrupoFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _miembrosGrupoFormKey = GlobalKey<FormState>();

  bool _isLoading = false;
  Map<String, dynamic> grupoData = {};
  Timer? _timer; // Temporizador para el tiempo de espera
  bool _dialogShown = false; // Evitar mostrar múltiples diálogos de error
  Set<String> originalMemberIds = {};


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentIndex = _tabController.index;
      });
    });
    fetchGrupoData(); // Llamar a la función para obtener los datos del grupo

    print('Grupo seleccionado: ${widget.idGrupo}');
  }

  // Función para obtener los detalles del grupo
  // Función para obtener los detalles del grupo
Future<void> fetchGrupoData() async {
  if (!mounted) return;
  
  print('Ejecutando fetchGrupoData');
  _timer?.cancel();

  setState(() => _isLoading = true);

  _timer = Timer(const Duration(seconds: 10), () {
    if (mounted && _isLoading && !_dialogShown) {
      setState(() => _isLoading = false);
      mostrarDialogoError(
        'No se pudo conectar al servidor. Por favor, revise su conexión de red.',
      );
      _dialogShown = true;
    }
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('tokenauth') ?? '';
    
    final url = 'http://$baseUrl/api/v1/grupodetalles/${widget.idGrupo}';
    final response = await http.get(
      Uri.parse(url),
      headers: {'tokenauth': token},
    );

    if (!mounted) return;
    _timer?.cancel();

    if (response.statusCode == 200) {
      final data = json.decode(response.body)[0];
      List<Map<String, dynamic>> clientesActuales = [];

      setState(() {
        grupoData = data;
        _isLoading = false;
        nombreGrupoController.text = data['nombreGrupo'] ?? '';
        descripcionController.text = data['detalles'] ?? '';
        selectedTipo = data['tipoGrupo'];
        
        _selectedPersons.clear();
        _cargosSeleccionados.clear();
        originalMemberIds.clear();

        if (data['clientes'] != null) {
          clientesActuales = List<Map<String, dynamic>>.from(data['clientes']);
          _selectedPersons.addAll(clientesActuales);
          originalMemberIds = Set.from(clientesActuales.map((c) => c['idclientes'].toString()));

          for (var cliente in clientesActuales) {
            String? idCliente = cliente['idclientes'];
            String? cargo = cliente['cargo'];
            if (idCliente != null && cargo != null) {
              _cargosSeleccionados[idCliente] = cargo;
              _originalCargos[idCliente] = cargo;
            }
          }
        }
      });

      print('Clientes actuales del grupo:');
      for (var cliente in clientesActuales) {
        print('id: ${cliente['idclientes']}, Nombre: ${cliente['nombres']}, Cargo: ${cliente['cargo']}');
      }
    } else {
      _handleResponseErrors(response);
    }
  } catch (e) {
    _handleNetworkError(e);
  } finally {
    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }
}

void _handleResponseErrors(http.Response response) {
  print('Error response body: ${response.body}');
  print('Status code: ${response.statusCode}');

  try {
    final dynamic errorData = json.decode(response.body);
    final String errorMessage = _extractErrorMessage(errorData);
    final int statusCode = response.statusCode;

    if (_isTokenExpiredError(statusCode, errorMessage)) {
      _handleTokenExpiration();
    } else if (statusCode == 404) {
      mostrarDialogoError('Recurso no encontrado (404)');
    } else {
      mostrarDialogoError('Error $statusCode: $errorMessage');
    }
  } catch (e) {
    mostrarDialogoError('Error desconocido: ${response.body}');
  }
}


String _extractErrorMessage(dynamic errorData) {
  try {
    return errorData?['error']?['message']?.toString() ?? 
           errorData?['Error']?['Message']?.toString() ?? 
           errorData?['message']?.toString() ?? 
           'Mensaje de error no disponible';
  } catch (e) {
    return 'Error al parsear mensaje';
  }
}

bool _isTokenExpiredError(int statusCode, String errorMessage) {
  final lowerMessage = errorMessage.toLowerCase();
  return statusCode == 401 || 
         statusCode == 403 || 
         (statusCode == 404 && lowerMessage.contains('token')) ||
         lowerMessage.contains('jwt') ||
         lowerMessage.contains('expir');
}


  // Función para mostrar el diálogo de error
 // Función para mostrar el diálogo de error
void mostrarDialogoError(String mensaje, {VoidCallback? onClose}) {
  if (!mounted) return;
  
  _dialogShown = true;
  showDialog(
    barrierDismissible: false,
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Error'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (onClose != null) onClose();
            },
            child: const Text('Aceptar'),
          ),
        ],
      );
    },
  ).then((_) => _dialogShown = false);
}

  bool _validarFormularioActual() {
    if (_currentIndex == 0) {
      return _infoGrupoFormKey.currentState?.validate() ?? false;
    } else if (_currentIndex == 1) {
      return _miembrosGrupoFormKey.currentState?.validate() ?? false;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> findPersons(String query) async {
    final url = Uri.parse('http://$baseUrl/api/v1/clientes/$query');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } else {
      throw Exception('Error al cargar los datos: ${response.statusCode}');
    }
  }

  Future<void> enviarGrupo() async {
  if (!mounted) return;
  
  if (nombreGrupoController.text.isEmpty ||
      descripcionController.text.isEmpty ||
      selectedTipo == null) {
    mostrarDialogoError("Por favor, completa todos los campos obligatorios.");
    return;
  }

  setState(() => _isLoading = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('tokenauth') ?? '';
    
    final response = await http.put(
      Uri.parse('http://$baseUrl/api/v1/grupos/${widget.idGrupo}'),
      headers: {
        'Content-Type': 'application/json',
        'tokenauth': token
      },
      body: json.encode({
        "nombreGrupo": nombreGrupoController.text,
        "detalles": descripcionController.text,
        "tipoGrupo": selectedTipo
      }),
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      widget.onGrupoEditado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grupo actualizado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      _handleTokenExpiration();
    } else {
      _handleApiError(response, 'Error al actualizar el grupo');
    }
  } catch (e) {
    _handleNetworkError(e);
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<void> _enviarMiembros(String idGrupo) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('tokenauth') ?? '';
    
    for (var persona in _selectedPersons) {
      if (originalMemberIds.contains(persona['idclientes'].toString())) continue;

      final miembroData = {
        'idgrupos': idGrupo,
        'idclientes': persona['idclientes'],
        'idusuarios': '6KNV796U0O',
        'nomCargo': _cargosSeleccionados[persona['idclientes']] ?? 'Miembro',
      };

      final response = await http.post(
        Uri.parse('http://$baseUrl/api/v1/grupodetalles/'),
        headers: {
          'Content-Type': 'application/json',
          'tokenauth': token
        },
        body: json.encode(miembroData),
      );

      if (response.statusCode != 201) {
        throw Exception('Error al agregar miembro: ${response.body}');
      }
    }
  } catch (e) {
    _handleNetworkError(e);
    rethrow;
  }
}

  Future<void> editarGrupo() async {
  if (!_validarFormularioActual()) return;

  setState(() => _isLoading = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('tokenauth') ?? '';
    
    // Actualizar grupo
    await enviarGrupo();

    // Eliminar miembros removidos
    await eliminarClienteGrupo(widget.idGrupo, token);

    // Actualizar cargos
    for (var cliente in _selectedPersons) {
      String idCliente = cliente['idclientes'].toString();
      String cargoEditado = _cargosSeleccionados[idCliente] ?? 'Miembro';
      
      if (originalMemberIds.contains(idCliente)) {
        await actualizarCargo(widget.idGrupo, idCliente, cargoEditado, token);
      }
    }

    // Agregar nuevos miembros
    await _enviarMiembros(widget.idGrupo);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grupo y miembros actualizados correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  } catch (e) {
    _handleNetworkError(e);
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}


  Future<void> eliminarClienteGrupo(String idGrupo, String token) async {
  if (_clientesEliminados.isEmpty) return;

  try {
    for (String idCliente in _clientesEliminados) {
      final response = await http.delete(
        Uri.parse('http://$baseUrl/api/v1/grupodetalles/$idGrupo/$idCliente'),
        headers: {'tokenauth': token},
      );

      if (response.statusCode != 200) {
        throw Exception('Error al eliminar cliente: ${response.body}');
      }
    }
  } finally {
    _clientesEliminados.clear();
  }
}


  void verificarCambios() async {
  if (!mounted) return;
  
  List<Map<String, dynamic>> cambios = [];
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('tokenauth') ?? '';

  _originalCargos.forEach((idCliente, cargoOriginal) {
    final cargoEditado = _cargosSeleccionados[idCliente];
    if (cargoOriginal != cargoEditado) {
      cambios.add({
        'idCliente': idCliente,
        'cargoOriginal': cargoOriginal,
        'cargoEditado': cargoEditado,
      });
    }
  });

  if (cambios.isNotEmpty) {
    print('Cambios detectados:');
    for (var cambio in cambios) {
      print('Cliente: ${cambio['idCliente']}, Cargo Original: ${cambio['cargoOriginal']}, Cargo Editado: ${cambio['cargoEditado']}');

      try {
        await actualizarCargo(
          widget.idGrupo, 
          cambio['idCliente'].toString(), // Asegurar conversión a String
          cambio['cargoEditado'].toString(), 
          token // Enviamos el token aquí
        );
      } catch (e) {
        if (mounted) {
          mostrarDialogoError('Error actualizando cargo: ${e.toString()}');
        }
      }
    }
  } else {
    print('No hay cambios detectados.');
  }
}

  Future<void> actualizarCargo(
  String idGrupo, 
  String idCliente,
  String nuevoCargo,
  String token,
) async {
  try {
    final response = await http.put(
      Uri.parse('http://$baseUrl/api/v1/grupodetalles/cargo/$idGrupo/$idCliente'),
      headers: {
        'Content-Type': 'application/json',
        'tokenauth': token
      },
      body: json.encode({'nomCargo': nuevoCargo}),
    );

    if (response.statusCode != 200) {
      throw Exception('Error actualizando cargo: ${response.body}');
    }
  } catch (e) {
    print('Error al actualizar cargo: $e');
    rethrow;
  }
}

// Funciones de ayuda para manejo de errores
void _handleTokenExpiration() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('tokenauth');
  
  if (mounted) {
    mostrarDialogoError(
      'Tu sesión ha expirado. Por favor inicia sesión nuevamente.',
      onClose: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      ),
    );
  }
}

void _handleApiError(http.Response response, String mensajeBase) {
  final errorData = json.decode(response.body);
  final mensajeError = errorData['error']?['message'] ?? 'Error desconocido';
  
  mostrarDialogoError(
    '$mensajeBase: $mensajeError (Código: ${response.statusCode})'
  );
}

void _handleNetworkError(dynamic e) {
  if (e is SocketException) {
    mostrarDialogoError('Error de conexión. Verifica tu conexión a internet.');
  } else {
    mostrarDialogoError('Error inesperado: ${e.toString()}');
  }
}

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.8;
    final height = MediaQuery.of(context).size.height * 0.8;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(20),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(),
              )
            : Column(
                children: [
                  Text(
                    'Editar Grupo',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  TabBar(
                    controller: _tabController,
                    labelColor: Color(0xFF5162F6),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Color(0xFF5162F6),
                    tabs: [
                      Tab(text: 'Información del Grupo'),
                      Tab(text: 'Miembros del Grupo'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 30, top: 10, bottom: 10, left: 0),
                          child: _paginaInfoGrupo(),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 30, top: 10, bottom: 10, left: 0),
                          child: _paginaMiembros(),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text('Cancelar'),
                      ),
                      Row(
                        children: [
                          if (_currentIndex > 0)
                            TextButton(
                              onPressed: () {
                                _tabController.animateTo(_currentIndex - 1);
                              },
                              child: Text('Atrás'),
                            ),
                          if (_currentIndex < 1)
                            ElevatedButton(
                              onPressed: () {
                                if (_validarFormularioActual()) {
                                  _tabController.animateTo(_currentIndex + 1);
                                } else {
                                  print(
                                      "Validación fallida en la pestaña $_currentIndex");
                                }
                              },
                              child: Text('Siguiente'),
                            ),
                          if (_currentIndex == 1)
                            ElevatedButton(
                              onPressed: () async {
                                setState(() {
                                  _isLoading =
                                      true; // Muestra el CircularProgressIndicator
                                });

                                try {
                                  await editarGrupo(); // Espera a que la función termine
                                } catch (e) {
                                  // Puedes manejar el error aquí si es necesario
                                  print("Error: $e");
                                } finally {
                                  if (mounted) {
                                    // Solo actualizamos el estado si el widget sigue montado
                                    setState(() {
                                      _isLoading =
                                          false; // Oculta el CircularProgressIndicator
                                    });
                                  }
                                }
                              },
                              child: _isLoading
                                  ? CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    )
                                  : Text('Guardar'),
                            )
                        ],
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  // Función que crea cada paso con el círculo y el texto
  Widget _buildPasoItem(int numeroPaso, String titulo, bool isActive) {
    return Row(
      children: [
        // Círculo numerado para el paso
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? Colors.white
                : Colors.transparent, // Fondo blanco solo si está activo
            border: Border.all(
                color: Colors.white,
                width: 2), // Borde blanco en todos los casos
          ),
          alignment: Alignment.center,
          child: Text(
            numeroPaso.toString(),
            style: TextStyle(
              color: isActive
                  ? Color(0xFF5162F6)
                  : Colors.white, // Texto rojo si está activo, blanco si no
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(width: 10),

        // Texto del paso
        Expanded(
          child: Text(
            titulo,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _paginaInfoGrupo() {
    int pasoActual = 1; // Paso actual que queremos marcar como activo
    const double verticalSpacing = 20.0; // Variable para el espaciado vertical

    return Form(
      key: _infoGrupoFormKey,
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
                color: Color(0xFF5162F6),
                borderRadius: BorderRadius.all(Radius.circular(20))),
            width: 250,
            height: 500,
            padding: EdgeInsets.symmetric(
                vertical: 20, horizontal: 10), // Espaciado vertical
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Paso 1
                _buildPasoItem(1, "Informacion del grupo", pasoActual == 1),
                SizedBox(height: 20),

                // Paso 2
                _buildPasoItem(2, "Integrantes del grupo", pasoActual == 2),
                SizedBox(height: 20),
              ],
            ),
          ),
          SizedBox(width: 50), // Espacio entre la columna y el formulario
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  // Contenedor circular de fondo rojo con el ícono
                  Container(
                    width: 120, // Ajustar tamaño del contenedor
                    height: 120,
                    decoration: BoxDecoration(
                      color: Color(0xFF5162F6), // Color de fondo rojo
                      shape: BoxShape.circle, // Forma circular
                    ),
                    child: Center(
                      child: Icon(
                        Icons.group,
                        size: 80, // Tamaño del ícono
                        color: Colors.white, // Color del ícono
                      ),
                    ),
                  ),
                  SizedBox(height: verticalSpacing), // Espacio debajo del ícono
                  _buildTextField(
                    controller: nombreGrupoController,
                    label: 'Nombres del grupo',
                    icon: Icons.person,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingrese el nombre del grupo';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: verticalSpacing),
                  _buildDropdown(
                    value: selectedTipo,
                    hint: 'Tipo',
                    items: tiposGrupo,
                    onChanged: (value) {
                      setState(() {
                        selectedTipo = value;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, seleccione el Tipo de Grupo';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: verticalSpacing),
                  _buildTextField(
                    controller: descripcionController,
                    label: 'Descripción',
                    icon: Icons.description,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingrese una descripción';
                      }
                      return null;
                    },
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paginaMiembros() {
    int pasoActual = 2; // Paso actual que queremos marcar como activo

    return Form(
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
                color: Color(0xFF5162F6),
                borderRadius: BorderRadius.all(Radius.circular(20))),
            width: 250,
            height: 500,
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Paso 1
                _buildPasoItem(1, "Informacion del grupo", pasoActual == 1),
                SizedBox(height: 20),

                // Paso 2
                _buildPasoItem(2, "Integrantes del grupo", pasoActual == 2),
                SizedBox(height: 20),
              ],
            ),
          ),
          SizedBox(width: 50), // Espacio entre la columna y el formulario
          Expanded(
            child: Column(
              children: [
                SizedBox(height: 20),
                TypeAheadField<Map<String, dynamic>>(
                  builder: (context, controller, focusNode) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Escribe para buscar',
                    ),
                  ),
                  decorationBuilder: (context, child) => Material(
                    type: MaterialType.card,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    child: child,
                  ),
                  suggestionsCallback: (search) async {
                    if (search.isEmpty) {
                      return [];
                    }
                    return await findPersons(search);
                  },
                  itemBuilder: (context, person) {
                    return ListTile(
                      title: Row(
                        children: [
                          Text(
                            '${person['nombres'] ?? ''} ${person['apellidoP'] ?? ''} ${person['apellidoM'] ?? ''}',
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(width: 10),
                          Text('-  F. Nacimiento: ${person['fechaNac'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.grey[700])),
                          SizedBox(width: 10),
                          Text('-  Teléfono: ${person['telefono'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.grey[700])),
                        ],
                      ),
                    );
                  },
                  onSelected: (person) {
                    // Verificar si la persona ya está en la lista usando el campo `idclientes`
                    bool personaYaAgregada = _selectedPersons
                        .any((p) => p['idclientes'] == person['idclientes']);

                    if (!personaYaAgregada) {
                      setState(() {
                        _selectedPersons.add(person);
                        _cargosSeleccionados[person['idclientes']] =
                            cargos[0]; // Rol predeterminado
                      });
                      _controller.clear();
                    } else {
                      // Mostrar mensaje indicando que la persona ya fue agregada
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'La persona ya ha sido agregada a la lista')));
                    }
                  },
                  controller: _controller,
                  loadingBuilder: (context) => const Text('Cargando...'),
                  errorBuilder: (context, error) =>
                      const Text('Error al cargar los datos!'),
                  emptyBuilder: (context) =>
                      const Text('No hay coincidencias!'),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: _selectedPersons.length,
                    itemBuilder: (context, index) {
                      final person = _selectedPersons[index];
                      final nombre = person['nombres'] ?? '';
                      final idCliente = person['idclientes'];
                      final telefono = person['telefono'] ?? 'No disponible';
                      final fechaNac =
                          person['fechaNacimiento'] ?? 'No disponible';

                      return ListTile(
                        title: Row(
                          children: [
                            // Mostrar numeración antes del nombre
                            Text(
                              '${index + 1}. ', // Numeración
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black),
                            ),
                            // Nombre completo
                            Expanded(
                              child: Text(
                                '${nombre} ${person['apellidoP'] ?? ''} ${person['apellidoM'] ?? ''}',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Teléfono
                            Text(
                              'Teléfono: $telefono',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey[700],
                              ),
                            ),
                            // Fecha de nacimiento
                            SizedBox(width: 30),
                            Text(
                              'Fecha de Nacimiento: $fechaNac',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Dropdown para seleccionar cargo
                            DropdownButton<String>(
                              value:
                                  _cargosSeleccionados[person['idclientes']] ??
                                      'Miembro',
                              onChanged: (nuevoCargo) {
                                setState(() {
                                  _cargosSeleccionados[person['idclientes']] =
                                      nuevoCargo!;
                                });
                              },
                              items:
                                  cargos.map<DropdownMenuItem<String>>((cargo) {
                                return DropdownMenuItem<String>(
                                  value: cargo,
                                  child: Text(cargo),
                                );
                              }).toList(),
                            ),
                            SizedBox(
                                width:
                                    8), // Espaciado entre el dropdown y el ícono
                            // Ícono de eliminar
                            IconButton(
                              onPressed: () async {
                                final confirmDelete = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Confirmar eliminación'),
                                    content: Text(
                                        '¿Estás seguro de que quieres eliminar a ${nombre} ${person['apellidoP'] ?? ''}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: Text('Eliminar'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmDelete == true) {
                                  setState(() {
                                    _clientesEliminados.add(idCliente);
                                    _selectedPersons.removeAt(index);
                                  });
                                }
                              },
                              icon: Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildTextField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  TextInputType keyboardType = TextInputType.text,
  String? Function(String?)? validator,
  double fontSize = 12.0, // Tamaño de fuente por defecto
  int? maxLength, // Longitud máxima opcional
}) {
  return TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    style: TextStyle(fontSize: fontSize),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(fontSize: fontSize),
    ),
    validator: validator, // Asignar el validador
    inputFormatters: maxLength != null
        ? [
            LengthLimitingTextInputFormatter(maxLength)
          ] // Limita a la longitud especificada
        : [], // Sin limitación si maxLength es null
  );
}

Widget _buildDropdown({
  required String? value,
  required String hint,
  required List<String> items,
  required void Function(String?) onChanged,
  double fontSize = 12.0,
  String? Function(String?)? validator,
}) {
  return DropdownButtonFormField<String>(
    value: value,
    hint: value == null
        ? Text(
            hint,
            style: TextStyle(fontSize: fontSize, color: Colors.black),
          )
        : null,
    items: items.map((item) {
      return DropdownMenuItem(
        value: item,
        child: Text(
          item,
          style: TextStyle(fontSize: fontSize, color: Colors.black),
        ),
      );
    }).toList(),
    onChanged: onChanged,
    validator: validator,
    decoration: InputDecoration(
      labelText: value != null ? hint : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black),
      ),
    ),
    style: TextStyle(fontSize: fontSize, color: Colors.black),
  );
}

