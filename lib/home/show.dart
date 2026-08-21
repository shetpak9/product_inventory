import 'package:flutter/material.dart';
import 'package:product_inventory/home/productlist.dart';
import 'package:product_inventory/shared/loading.dart';

class Show extends StatefulWidget {
  const Show({super.key});

  @override
  State<Show> createState() => _ShowState();
}

class _ShowState extends State<Show> {

  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return loading ? Loading() : Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child:Container(
          padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
          child: Center(
            child: Column(
              children: [
                Image(
                  image: AssetImage('assets/rabbit-playing-ball-mascot-logo_530521-1534.png'),
                  width: 300,
                  height: 250,
                ),
                Text(
                  'Hello',
                  style: TextStyle(
                    fontSize: 50.0,
                    fontWeight: FontWeight(1000)
                  ),
                ),
                SizedBox(height: 10.0,),
                Text(
                  'Product List',
                  style: TextStyle(
                    fontSize: 15.0,
                  ),
                ),
                Expanded(child: ProductList())
              ]
            )
          )
        )
      )
    );
  }
}