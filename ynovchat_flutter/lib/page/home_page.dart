import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ynovchat_flutter/bo/message.dart';
import 'package:ynovchat_flutter/routes.dart';
import 'package:latlng/latlng.dart';
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  //ScrollController? sc;
  late StreamController<List<Message>> _streamControllerListMsgs;
  late Stream<List<Message>> _streamMsgs;
  late TextEditingController tecMsg;
  final ImagePicker ip = ImagePicker();
  bool modeImagePicked = false;
  String imageBasee64Content = "";

  @override
  void initState() {
    super.initState();
    //Intl
    initializeDateFormatting('fr_FR', null);
    //TimeAgo
    setLocaleMessages("fr_short", FrShortMessages());
    tecMsg = TextEditingController(text: "");
    _streamControllerListMsgs = StreamController<List<Message>>();
    _streamMsgs = _streamControllerListMsgs.stream;
    fetchMessages();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ynov Chat"),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          Row(
            children: [
              IconButton(
                onPressed: _pickImage,
                icon: const Icon(Icons.image)
              ),
              IconButton(
                onPressed: _locateMe,
                icon: const Icon(Icons.my_location)
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextFormField(
                    controller: tecMsg,
                    decoration: const InputDecoration(hintText: "Tapez votre message..."),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => _sendMsg(),
                child: const Icon(Icons.send)
              )
            ],
          ),
        ],
      )
    );
  }

  void _pickImage() async{
    XFile? imagePicked = await
      ip.pickImage(source: ImageSource.gallery,imageQuality: 10);
    if(imagePicked != null){
      modeImagePicked = true;
      log(imagePicked.name);
      Uint8List imageBytes = await imagePicked.readAsBytes();
      imageBasee64Content = base64Encode(imageBytes.toList());
      tecMsg.text = imagePicked.path;
      log(base64Encode(imageBytes.toList()));
    }
  }

  void _locateMe() async{
    // Check si la localisation est activée
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    // Check si on a la permission
    LocationPermission permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied) {
      Geolocator.requestPermission();
    } else if (permission == LocationPermission.deniedForever)
      return;
    // Récupérer la localisation et l'ajouter dans l'input text
    if(serviceEnabled && permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse) {
      Geolocator.getCurrentPosition().then(
          (position) {
            tecMsg.text =
              '${position.latitude},${position.longitude}';
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Votre position a été récupérée")));
          },
        onError: (error, stacktrace)
          => log("Erreur lors de la récupération de la position:${error.toString()}")
      );
    }
  }

  StreamBuilder<List<Message>> _buildList() {
    return StreamBuilder<List<Message>>(
      stream: _streamMsgs,
      builder: (context, snapshot) {
        if(snapshot.hasError) {
          return const Center(child:  Icon(Icons.error));
        }
        if(!snapshot.hasData) {
          return const Center(child: const CircularProgressIndicator());
        } else {
          //sc = ScrollController();
          return ListView.separated(
            //controller: sc,
            itemCount: snapshot.data!.length,
            separatorBuilder:
              (BuildContext context, int index) => const Divider(/*thickness: 1.5,*/),
            itemBuilder: (context, index) =>
              InkWell(
                onTap: () {_launchUrl(snapshot.data![index].content);},
                onLongPress: (){},
                child: ListTile(
                  //leading: Image.network('https://fujifilm-x.com/wp-content/uploads/2019/08/x-t3_sample-images02.jpg'),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(snapshot.data![index].author.username),
                      Text(formatDateString(snapshot.data![index].created_at),
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ]
                  ,),
                  subtitle: snapshot.data![index].isImage ?
                            Image.memory(base64Decode(snapshot.data![index].content)) :
                            Text(snapshot.data![index].content),
            ),
              )
          );
        }
      }
    );
  }

  void _launchUrl(String content){
    //TODO Parser le content pour savoir si c'est une url
    RegExp urlRegex = RegExp(r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?");
    RegExp latLngRegex = RegExp(r"^(-?\d+(\.\d+)?),\s*(-?\d+(\.\d+)?)$");
    bool isUri = urlRegex.hasMatch(content);
    //TODO Lancer l'url dans un naviguateur (WebView)
    if(isUri){
      launch(urlRegex.firstMatch(content)?.group(0) ?? "");
    }else{
      String? latLngUri =  latLngRegex.firstMatch(content)?.group(0);
      if(latLngUri != null){
        double latitude = double.parse(latLngUri.split(',')[0]);
        String? longitudeS =latLngUri.split(',')[1];
        if(longitudeS != null){
          double longitude =  double.parse(longitudeS);
          Navigator.of(context).pushNamed(
            ROUTE_MAP_PAGE,
            arguments:LatLng(latitude,longitude));
        }
      }
    }


  }

  String formatDateString(String isoDate){
    DateFormat df = DateFormat("yyyy-MM-ddTHH:mm:ss.SSSZ");
    DateTime dateTime = df.parseUTC(isoDate).toLocal() ;
    return format(dateTime,locale: 'fr_short');
  }

  void fetchMessages() async{
    String jwt = await const FlutterSecureStorage().read(key: "jwt") ?? "";
    // Si pas de token, redirection vers login
    if(jwt.isEmpty) {
      Navigator.of(context).pushReplacementNamed(ROUTE_LOGIN);
    }
    Future<Response> resMsgs = get(
      Uri.parse("https://flutter-learning.mooo.com/messages?_limit=999"),
      headers: {"Authorization":"Bearer $jwt"}
    );
    resMsgs.then(
      (value) {
        if(value.statusCode==200){
          String jsonBody = value.body;
          List<Message> lsMsgs = List.empty(growable: true);
          for(Map<String,dynamic> msg in jsonDecode(jsonBody)){
            lsMsgs.add(Message.fromJson(msg));
          }
          _streamControllerListMsgs.sink.add(lsMsgs);
        }
      },
      onError: (_, err) => log("Erreur lors du download des msgs:" + err.toString())
    );
  }

  void _sendMsg() async{
    if(tecMsg.value.text.trim().isEmpty)
      return;
    String jwt = await const FlutterSecureStorage().read(key: "jwt") ?? "";
    Future<Response> resPost = post(
      Uri.parse("https://flutter-learning.mooo.com/messages"),
      headers: {"Authorization":"Bearer $jwt"},
      body: {
        "content" : modeImagePicked ? imageBasee64Content :
          tecMsg.value.text.trim(),
        "isImage" : modeImagePicked.toString()
      }
    );
    resPost.then(
        (value) {
        if(value.statusCode==200){
          tecMsg.text = "";
          if(modeImagePicked){
            imageBasee64Content = "";
            modeImagePicked = false;
          }
          fetchMessages();
        }
      },
      onError: (_, err) => log("Erreur lors de l'envoi du msg:" + err.toString())
    );
  }

  @override
  void dispose() {
    _streamControllerListMsgs.close();
  }
}

