import 'package:flutter/material.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/constant.dart';
import 'package:product_inventory/shared/loading.dart';

class Create extends StatefulWidget {
  const Create({super.key});

  @override
  State<Create> createState() => _CreateState();
}

class _CreateState extends State<Create> {

  String productName = "";
  double? price;
  String productType = "";
  String error = "";
  bool loading = false;

  final List<String> itemType = ['Beverage', 'Snack', 'Personal Care','Cosmetics','Electronics'];
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return loading ? Loading() : Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
          
          child: SingleChildScrollView(
            child:Container(
            padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 40.0),
            child: Center(
              child: Column(
                children: [
                  Image(image: 
                    AssetImage('assets/rabbit-playing-ball-mascot-logo_530521-1534.png'),
                    width: 300.0,
                    height: 250.0,
                  ),
                  Text(
                    'Hello',
                    style: TextStyle(
                      fontSize:50.0,
                      fontWeight: FontWeight(1000),
                    ),
                  ),
                  SizedBox(height: 10.0,),
                  Text(
                    'Create a Product',
                    style: TextStyle(
                      fontSize: 15.0,
                    ),
                  ),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: <Widget>[
                        SizedBox(height: 20.0,),
                        TextFormField(
                          controller: _productNameController,
                          decoration: textInputDecoration.copyWith(hintText: 'Product'),
                          validator: (val) => val!.isEmpty ? 'Enter a Product' : null,
                          onChanged: (val){
                            setState(() => productName = val);
                          },
                        ),
                        SizedBox(height: 16.0,),
                        TextFormField(
                          controller: _priceController,
                          decoration: textInputDecoration.copyWith(hintText: 'Price'),
                          validator: (val) => (val == null) || val.isEmpty ? 'Enter a Price' : null,
                          onChanged: (val){
                            setState(() => price = double.tryParse(val) ?? 0.0);
                          },
                        ),
                        SizedBox(height: 16.0,),
                        DropdownButtonFormField(
                          decoration: textInputDecoration.copyWith(hintText: 'Product Type'),
                          items: itemType.map((item){
                            return DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            );
                          }).toList(),
                          onChanged: (value) => productType = value as String,
                        ),
                        SizedBox(height: 16.0,),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple[400],
                            foregroundColor: Colors.white
                          ),
                          child: Text(
                            'Create'
                          ),
                          onPressed: () async {  
                            final form = _formKey.currentState;

                            if (form == null || !form.validate()) {
                              return;
                            }
                            setState(() => loading = true);
                            final success = await DatabaseService().addProduct(productName,price,productType);

                            if(!mounted) return;

                            setState(() {
                              error = success ? 'Product Created' : 'Error occurred';
                              productName = '';
                              price = 0.0;
                              productType = '';
                              loading = false;
                            });

                            _productNameController.clear();
                            _priceController.clear();

                            await Future.delayed(const Duration(seconds: 2));
                            
                            if(!mounted) return;

                            setState(() {
                              error = '';
                            });
                          }, 
                        ),
                        SizedBox(height: 16.0,),
                        Text(
                          error,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14.0,
                          )
                        ),
                      ],
                    )
                  ),
                ],
              ),
            ),
          ),
        )
      )
    );
  }
}