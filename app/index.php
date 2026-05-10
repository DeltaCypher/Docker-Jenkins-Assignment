<?php
// app/index.php  – simple health-check page
echo "<h1>Docker Stack is Running!</h1>";
echo "<p>PHP Version: " . phpversion() . "</p>";
echo "<p>Server Time: " . date('Y-m-d H:i:s') . "</p>";
