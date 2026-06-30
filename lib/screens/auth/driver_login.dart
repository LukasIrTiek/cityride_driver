import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'driver_register.dart';

class DriverLoginPage extends StatefulWidget {

  const DriverLoginPage({super.key});

  @override
  State<DriverLoginPage> createState() =>
      _DriverLoginPageState();
}

class _DriverLoginPageState
    extends State<DriverLoginPage> {

  final supabase =
      Supabase.instance.client;

  final emailController =
  TextEditingController();

  final passwordController =
  TextEditingController();

  bool loading = false;

  Future<void> login() async {

    if (emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      return;
    }

    try {

      setState(() {
        loading = true;
      });

      await supabase.auth
          .signInWithPassword(

        email:
        emailController.text.trim(),

        password:
        passwordController.text.trim(),
      );

      if (mounted) {

        Navigator.pushReplacement(

          context,

          MaterialPageRoute(
            builder: (_) =>
            const AuthGate(),
          ),
        );
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

  Future<void> forgotPassword() async {

    if (emailController.text.isEmpty) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content: Text(
            'Įveskite el. paštą',
          ),
        ),
      );

      return;
    }

    try {

      await supabase.auth
          .resetPasswordForEmail(
        emailController.text.trim(),
      );

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            'Slaptažodžio atstatymo nuoroda išsiųsta',
          ),
        ),
      );

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

      resizeToAvoidBottomInset: true,

      body: SafeArea(

        child: SingleChildScrollView(

          padding:
          const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),

          child: ConstrainedBox(

            constraints: BoxConstraints(
              minHeight:
              MediaQuery.of(context)
                  .size
                  .height -
                  80,
            ),

            child: IntrinsicHeight(

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
                    'Driver App',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 50),

                  TextField(

                    controller:
                    emailController,

                    keyboardType:
                    TextInputType
                        .emailAddress,

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

                  const SizedBox(height: 14),

                  Align(

                    alignment:
                    Alignment.centerRight,

                    child: GestureDetector(

                      onTap:
                      forgotPassword,

                      child: const Text(

                        'Pamiršai slaptažodį?',

                        style: TextStyle(
                          color: Colors.red,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 34),

                  SizedBox(

                    width: double.infinity,
                    height: 60,

                    child: ElevatedButton(

                      onPressed:
                      loading
                          ? null
                          : login,

                      style:
                      ElevatedButton
                          .styleFrom(

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
                          color:
                          Colors.white,
                        ),
                      )

                          : const Text(

                        'Prisijungti',

                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(

                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [

                      const Text(
                        'Neturi paskyros?',
                      ),

                      GestureDetector(

                        onTap: () {

                          Navigator.push(

                            context,

                            MaterialPageRoute(

                              builder: (_) =>
                              const DriverRegisterPage(),
                            ),
                          );
                        },

                        child: const Padding(

                          padding:
                          EdgeInsets.only(
                            left: 6,
                          ),

                          child: Text(

                            'Registruotis',

                            style: TextStyle(
                              color: Colors.red,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}