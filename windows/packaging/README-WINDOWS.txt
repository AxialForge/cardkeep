CardKeep for Windows
====================

CardKeep keeps your business-card contacts on your own computer. This is the Windows
version: it holds your contacts, lets you import and export them, and syncs with the
CardKeep app on your phone over your home network. It has no installer and needs no
administrator rights.

Run it
------
1. Unzip this download into a folder of its own, for example
   C:\Users\<you>\CardKeep   (right-click the zip, Extract All).
   Do not unzip it loose onto the Desktop or into Downloads: CardKeep updates itself by
   swapping its folder, so it needs a folder to itself.
2. Open that folder and double-click CardKeep.exe.
3. The first time, Windows may say "Windows protected your PC" because this app is not
   from the Microsoft Store. Choose "More info", then "Run anyway".
   Syncing needs no firewall change: the PC only ever calls the phone.

Update it
---------
Open Settings, then Updates, then "Check for updates". If a newer version is on GitHub,
CardKeep downloads it, checks the file against its published checksum, closes, swaps in
the new version and opens again. The version you had is kept for a short time; if the new
one will not start, CardKeep puts the old one back and tells you.
Nothing is checked in the background unless you switch on "Check when CardKeep opens".
Only github.com is contacted, and nothing about you is sent.

Your contacts
-------------
Contacts, card photos and backups are kept in your Documents folder, not in the CardKeep
folder, so updating or deleting the program folder never touches them. To move CardKeep
to another PC, use Export and backup on this one and Restore on the other.

Sync with the phone
-------------------
On the phone open Sync, then show the code to the PC's webcam (or tap Copy code text and paste it into the PC),
and keep both on the same Wi-Fi. If the webcam picture looks soft, hold the phone 40 to
60 centimetres from the camera and tap the code on the phone to make it big and bright.

Remove it
---------
Close CardKeep and delete its folder. Your contacts stay in Documents until you delete
them there.

If something goes wrong
-----------------------
The last update's log is %TEMP%\cardkeep-update\update.log.
