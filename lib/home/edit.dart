import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/constant.dart';
import 'package:product_inventory/shared/loading.dart';

class EditForm extends StatefulWidget {
  final Product product;
  const EditForm({super.key, required this.product});

  @override
  State<EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<EditForm> {

  final _formKey = GlobalKey<FormState>();
  final List<String> itemType = ['Beverage', 'Snack', 'Personal Care','Cosmetics','Electronics'];

  String? _currentProductName;
  double? _currentPrice;
  String? _currentProductType;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Product?>(
      stream: DatabaseService().getProduct(widget.product.id), 
      builder: (context, snapshot){
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        return loading ? Loading() : Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Text(
                'Edit Product Data',
                style: TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight(1000),
                ),
              ),
              SizedBox(height: 20.0,),
              TextFormField(
                initialValue: widget.product.name,
                decoration: textInputDecoration,
                validator: (val) => val!.isEmpty ? 'Please enter a name' : null,
                onChanged: (val) => setState(() => _currentProductName = val),
              ),
              SizedBox(height: 20.0,),
              TextFormField(
                initialValue: widget.product.price.toString(),
                decoration: textInputDecoration,
                validator: (val) => (val == null) || val.isEmpty ? 'Please enter a price' : null,
                onChanged: (val) => setState(() => _currentPrice = double.tryParse(val)),
              ),
              SizedBox(height: 20.0,),
              DropdownButtonFormField(
                decoration: textInputDecoration.copyWith(hintText: 'Product Type'),
                items: itemType.map((item){
                  return DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _currentProductType = value as String),
              ),
              SizedBox(height: 15.0,),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white
                ),
                child: Text(
                  'Update'
                ),
                onPressed: () async {
                  final form = _formKey.currentState;

                  if(form == null || !form.validate()){
                    return;
                  }
                  setState(() => loading = true);
                  await DatabaseService().updateUserData(
                    widget.product.id, 
                    _currentProductName ?? widget.product.name, 
                    _currentPrice ?? widget.product.price, 
                    _currentProductType ?? widget.product.productType
                  );

                  setState(() => loading = false);

                  if(!context.mounted) return;

                  Navigator.pop(context);
                },
              )
            ],
          )
        );
      }
    );
  }
}