import 'package:firebase_database/firebase_database.dart';
import 'package:product_inventory/model/product.dart';

class DatabaseService {

  final DatabaseReference productRef = FirebaseDatabase.instance.ref('products');

  Future<bool> addProduct(String name,double? price,String? productType) async {
    try {
      final ref = productRef.push();
      if(price == null){
        return false;
      }
      await ref.set({
        'name': name,
        'price': price,
        'productType': productType,
      });
      return true;
    } catch (e) {
        print(e);
        return false;
    }
  }
  
  Future<bool> updateUserData(String productId, String name, double price, String productType) async {
    try{
      await productRef.child(productId).update({
        'name' : name,
        'price': price,
        'productType': productType,
      });
      return true;
    }
    catch(e){
      print(e);
      return false;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    try{
      await productRef.child(productId).remove();
      return true;
    }
    catch(e){
      print(e);
      return false;
    }
  }

  List<Product> productListFromSnapshot(DataSnapshot snapshot){
      final data = snapshot.value as Map<Object?, Object?>?;

      if (data == null) {
        return [];
      }
      return data.entries.map((entry) {
      final product = Map<String, dynamic>.from(
        entry.value as Map,
      );

      return Product(
        id: entry.key.toString(),
        name: product['name'] as String,
        productType: product['productType'] as String,
        price: (product['price'] as num).toDouble(),
      );
    }).toList();  
  }

  Stream<List<Product>> get products {
    return productRef.onValue.map(
      (event) => productListFromSnapshot(event.snapshot),
    );
  }
  Stream<Product?> getProduct(String productId) {
    return productRef.child(productId).onValue.map((event){
      final data = event.snapshot.value;

      if (data == null){
        return null;
      }

      final product = Map<String, dynamic>.from(data as Map);

      return Product(
        id: productId, 
        name: product['name'] as String, 
        productType: product['productType'] as String, 
        price: (product['price'] as num).toDouble(),
      );
    });
  }

}