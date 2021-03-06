<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| contains the "web" middleware group. Now create something great!
|
*/

class Hello extends \sonvq\Cassandra\Eloquent\Model {
    protected $collection = 'hello';
}

Route::get('/', function () {
    Hello::query()->get();
    return view('welcome');
});
