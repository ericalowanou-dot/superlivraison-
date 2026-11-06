<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Models\City;
use App\Models\Country;
use App\Models\Language;
use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        Language::updateOrCreate(['code' => 'fr'], ['name' => 'Français']);

        $togo = Country::updateOrCreate(['code' => 'TG'], ['name' => 'Togo', 'dial_code' => '+228', 'currency' => 'XOF']);
        City::updateOrCreate(['country_id' => $togo->id, 'name' => 'Lomé']);

        // Administrateur de départ : ses identifiants viennent du fichier .env, jamais du code.
        if (($email = env('ADMIN_EMAIL')) && ($password = env('ADMIN_PASSWORD'))) {
            $admin = User::firstOrNew(['email' => $email]);
            $admin->forceFill(['name' => 'Administrateur', 'password' => $password, 'role' => Role::Admin, 'is_active' => true])->save();
        }
    }
}
