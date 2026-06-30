import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverRegisterPage extends StatefulWidget {

  const DriverRegisterPage({super.key});

  @override
  State<DriverRegisterPage> createState() =>
      _DriverRegisterPageState();
}

class _DriverRegisterPageState
    extends State<DriverRegisterPage> {

  final supabase =
      Supabase.instance.client;

  final fullNameController =
  TextEditingController();

  final emailController =
  TextEditingController();

  final passwordController =
  TextEditingController();

  bool loading = false;

  Future<void> register() async {

    if (fullNameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      return;
    }

    try {

      setState(() {
        loading = true;
      });

      final response =
      await supabase.auth.signUp(

        email:
        emailController.text.trim(),

        password:
        passwordController.text.trim(),
      );

      final user = response.user;

      if (user != null) {

        await supabase
            .from('drivers')
            .insert({

          'id': user.id,

          'full_name':
          fullNameController.text.trim(),

          'email':
          emailController.text.trim(),

          'online': false,

          'approved': false,

          'documents_uploaded': false,
        });
      }

      if (mounted) {

        ScaffoldMessenger.of(context)
            .showSnackBar(

          const SnackBar(

            backgroundColor:
            Colors.green,

            content: Text(
              'Paskyra sukurta',
            ),
          ),
        );

        await supabase.auth.signOut();

        Navigator.pop(context);
      }

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            e.toString(),
          ),
        ),
      );

    } finally {

      setState(() {
        loading = false;
      });
    }
  }

  InputDecoration inputStyle(
      String hint,
      IconData icon,
      ) {

    return InputDecoration(

      hintText: hint,

      prefixIcon: Icon(
        icon,
        color: Colors.red,
      ),

      filled: true,

      fillColor: Colors.white,

      contentPadding:
      const EdgeInsets.symmetric(
        vertical: 20,
      ),

      border: OutlineInputBorder(

        borderRadius:
        BorderRadius.circular(22),

        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Colors.white,

      body: SafeArea(

        child: Padding(

          padding:
          const EdgeInsets.symmetric(
            horizontal: 24,
          ),

          child: Column(

            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [

              const Spacer(),

              const Text(
                'CityRide',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight:
                  FontWeight.w900,
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Driver registracija',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 50),

              TextField(

                controller:
                fullNameController,

                decoration: inputStyle(
                  'Vardas Pavardė',
                  Icons.person_rounded,
                ),
              ),

              const SizedBox(height: 18),

              TextField(

                controller:
                emailController,

                keyboardType:
                TextInputType.emailAddress,

                decoration: inputStyle(
                  'El. paštas',
                  Icons.email_rounded,
                ),
              ),

              const SizedBox(height: 18),

              TextField(

                controller:
                passwordController,

                obscureText: true,

                decoration: inputStyle(
                  'Slaptažodis',
                  Icons.lock_rounded,
                ),
              ),

              const SizedBox(height: 34),

              SizedBox(

                width: double.infinity,
                height: 60,

                child: ElevatedButton(

                  onPressed:
                  loading ? null : register,

                  style:
                  ElevatedButton.styleFrom(

                    backgroundColor:
                    Colors.red,

                    foregroundColor:
                    Colors.white,

                    elevation: 0,

                    shape:
                    RoundedRectangleBorder(

                      borderRadius:
                      BorderRadius.circular(
                        22,
                      ),
                    ),
                  ),

                  child: loading

                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                    CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  )

                      : const Text(

                    'Registruotis',

                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Center(

                child: GestureDetector(

                  onTap: () {
                    Navigator.pop(context);
                  },

                  child: const Text(

                    'Jau turi paskyrą? Prisijungti',

                    style: TextStyle(
                      color: Colors.red,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}