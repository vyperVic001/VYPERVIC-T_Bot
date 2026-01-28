import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(VypervicV2App());
}

class VypervicV2App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VYPERVIC V2',
      theme: ThemeData.dark(),
      home: DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> signals = [];
  double totalPnL = 0.0;

  @override
  void initState() {
    super.initState();
    loadAccounts();
    runEngineCycle();
  }

  Future<void> loadAccounts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      accounts = List<Map<String, dynamic>>.from(
        prefs.getStringList('accounts')?.map((e) => Map<String, dynamic>.from(json.decode(e))) ?? []
      );
    });
  }

  Future<void> addAccount(String server, int login, String password) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var account = {'server': server, 'login': login, 'password': password};
    accounts.add(account);
    
    var accountList = accounts.map((e) => json.encode(e)).toList();
    await prefs.setStringList('accounts', accountList);
    
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Account $login added!')));
  }

  Future<void> runEngineCycle() async {
    // Firebase Cloud Function → C++ Engine (Serverless!)
    var response = await http.post(
      Uri.parse('https://us-central1-your-project.cloudfunctions.net/vypervic-cycle'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'accounts': accounts}),
    );
    
    if (response.statusCode == 200) {
      var data = json.decode(response.body);
      setState(() {
        signals = List<Map<String, dynamic>>.from(data['signals']);
        totalPnL = data['pnl'];
      });
      
      // Telegram Auto
      await sendTelegram(data['signals']);
    }
  }

  Future<void> sendTelegram(List signals) async {
    await http.post(Uri.parse('https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage'),
      body: {'chat_id': CHANNEL_ID, 'text': '🔥 V2 Signals: ${signals.length}'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('VYPERVIC V2 Engine'), backgroundColor: Colors.black),
      body: Column(
        children: [
          // P&L Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            color: totalPnL > 0 ? Colors.green : Colors.red,
            child: Text('P&L: \$${totalPnL.toStringAsFixed(2)}', 
                       style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          
          // Accounts Manager
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Server'))),
                      SizedBox(width: 10),
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Login'))),
                      SizedBox(width: 10),
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Password'), obscureText: true)),
                      IconButton(icon: Icon(Icons.add), onPressed: () => addAccount('','','')),
                    ],
                  ),
                ),
                Expanded(child: ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text('Login: ${accounts[i]['login']}'),
                    trailing: IconButton(icon: Icon(Icons.delete), onPressed: () => deleteAccount(i)),
                  ),
                )),
              ],
            ),
          ),
          
          // Signals + Execute
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: signals.length,
              itemBuilder: (context, i) {
                var sig = signals[i];
                return Card(
                  color: sig['confidence'] > 85 ? Colors.green : Colors.orange,
                  child: ListTile(
                    title: Text('${sig['symbol']} ${sig['direction']}'),
                    subtitle: Text('${sig['confidence']}% | Hacker: ${sig['hacker']}'),
                    trailing: ElevatedButton(
                      child: Text('EXECUTE'),
                      onPressed: () => executeTrade(sig),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Controls
          Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: runEngineCycle, child: Text('RUN CYCLE')),
                ElevatedButton(onPressed: () => sendTelegram(signals), child: Text('TELEGRAM')),
                FloatingActionButton.extended(onPressed: () {}, label: Text('Gemini Verify')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
