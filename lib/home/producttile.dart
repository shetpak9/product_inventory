import 'package:flutter/material.dart';
import 'package:product_inventory/home/edit.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/service/database.dart';

class Producttile extends StatelessWidget {

  

  final Product product;
  const Producttile({super.key, required this.product});

  @override
  Widget build(BuildContext context) {

    void showSettingsPanel() {
      showModalBottomSheet(
        context: context, 
        builder: (context) {
          return Container(
            padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 60.0),
            child: EditForm(product: product,),
          );
        }
      );
    }
    return Padding(
      padding: EdgeInsetsGeometry.only(top: 8.0),
      child: Card(
        margin: EdgeInsets.fromLTRB(20.0, 6.0, 20.0, 0.0),
        child: ListTile(
          leading: Icon(Icons.paste_rounded),
          title: Text("${product.name} - ${product.type}"),
          subtitle: Text("P${product.price}"),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                showSettingsPanel();
              }

              if (value == 'delete') {
                // Delete product
                final success = await DatabaseService().deleteProduct(product.id);

                if(!context.mounted) return ;

                if(success){
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Product Deleted')),
                  );
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.update),
                    SizedBox(width: 5.0,),
                    Text('Edit')
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete),
                    SizedBox(width: 5.0,),
                    Text('Delete')
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}