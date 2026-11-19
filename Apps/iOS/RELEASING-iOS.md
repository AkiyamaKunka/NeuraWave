# Releasing the iPhone app

The **iOS release** workflow (`.github/workflows/ios-release.yml`) builds, signs and
uploads the app to App Store Connect. It can also push the App Store listing in
`Apps/iOS/AppStore/` and submit the version to App Review (`scripts/asc.py`).

## One-time setup (owner, on the website)

1. **Create the app record.** In [App Store Connect](https://appstoreconnect.apple.com/apps)
   choose **+ → New App**:
   - Platform: iOS
   - Name: NeuraWave
   - Language: English (U.S.)
   - Bundle ID: com.akiyamakunka.NeuraWave
   - SKU: neurawave-ios
   - Full access
2. **Create an API key.** Go to Users and Access → Integrations → App Store Connect API → Team Keys → **+**.
   - Name it "NeuraWave CI" and give it the **Admin** role. Cloud signing needs Admin to create the distribution certificate.
   - Download the `.p8` file. Apple only lets you download it once.
3. **Add three repository secrets.** In GitHub, go to NeuraWave → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID`: the key ID from the list.
   - `ASC_ISSUER_ID`: the Issuer ID shown above the list.
   - `ASC_API_KEY_P8_BASE64`: the output of `base64 -i AuthKey_XXXX.p8 | pbcopy`, pasted.
4. **Answer App Privacy.** In the app's page, go to App Privacy → Get Started and choose
   **"No, we do not collect data from this app"**. The API can't set this answer. See
   [PRIVACY.md](../../PRIVACY.md) for why that's accurate.
5. **Set the review contact (only needed before submitting).** On the Variables tab of the
   same GitHub page, add `ASC_CONTACT_FIRST_NAME`, `ASC_CONTACT_LAST_NAME`,
   `ASC_CONTACT_EMAIL` and `ASC_CONTACT_PHONE`. Write the phone number with its country
   code, e.g. +1 555 123 4567.

## Shipping a build

- **TestFlight only:** go to Actions → iOS release → Run workflow, and untick both boxes.
- **TestFlight plus listing:** run it with the defaults. The listing covers the text,
  screenshots, category, age rating, free price, and attaching the build.
- **Submit for review:** tick **submit**, or push a tag `ios-v1.0` that matches
  `MARKETING_VERSION` in `project.yml`.

The build number is `BUILD_NUMBER_OFFSET + run_number`, which keeps every run above the
hand-made build 1. For a new version, bump `MARKETING_VERSION` in `Apps/iOS/project.yml`.

## If the upload step fails

The manual route uses the archive on the Mac. In the NeuraWave-AppStore folder, run:

```sh
xcodebuild -exportArchive -archivePath build/NeuraWave.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

Then run the workflow again. `scripts/asc.py` works on whatever build is uploaded.
