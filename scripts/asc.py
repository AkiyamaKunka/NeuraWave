#!/usr/bin/env python3
"""App Store Connect chores for the iPhone app, driven by the release workflow.

  asc.py wait-build <build-number>   wait until the uploaded build is processed
  asc.py testflight <build-number>   set its "What to Test" text
  asc.py listing <build-number>      push Apps/iOS/AppStore (text, screenshots,
                                     category, age rating, price, review notes)
                                     and attach the build to version 1.x
  asc.py submit                      send that version to App Review

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the AuthKey_*.p8) in the
environment. App Review contact details come from ASC_CONTACT_FIRST_NAME,
ASC_CONTACT_LAST_NAME, ASC_CONTACT_EMAIL and ASC_CONTACT_PHONE.

Two things the API can't do and the owner does once on the website: create the
app record, and answer the App Privacy questions ("Data Not Collected").
"""
import hashlib
import json
import os
import pathlib
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
ROOT = pathlib.Path(__file__).resolve().parent.parent
STORE = ROOT / "Apps/iOS/AppStore"
LISTING = json.loads((STORE / "listing.json").read_text())
SCREENSHOTS = {
    # 1320x2868 (6.9-inch) screenshots go in the 6.7-inch slot; Apple scales
    # them down for every smaller iPhone.
    "APP_IPHONE_67": sorted((STORE / "screenshots/iphone-6.9").glob("*.png")),
}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def token():
    key = pathlib.Path(os.environ["ASC_KEY_PATH"]).read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    response = requests.request(
        method,
        path if path.startswith("http") else API + path,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
        json=body,
        params=params,
        timeout=60,
    )
    if response.status_code not in ok:
        fail(f"{method} {path} -> {response.status_code}: {response.text[:2000]}")
    return response.json() if response.content else {}


def ref(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def app_id():
    apps = call("GET", "/v1/apps", params={"filter[bundleId]": LISTING["bundleId"]})["data"]
    if not apps:
        fail(
            f"No App Store Connect app for {LISTING['bundleId']}. Create it once at "
            "https://appstoreconnect.apple.com/apps (+, New App, iOS, that bundle ID)."
        )
    return apps[0]["id"]


def find_build(app, number):
    builds = call("GET", "/v1/builds", params={"filter[app]": app, "filter[version]": str(number), "limit": 1})["data"]
    return builds[0] if builds else None


def wait_build(number):
    app = app_id()
    deadline = time.time() + 45 * 60
    while time.time() < deadline:
        build = find_build(app, number)
        state = build["attributes"]["processingState"] if build else "NOT_YET_VISIBLE"
        print(f"build {number}: {state}")
        if state == "VALID":
            return build
        if state in ("FAILED", "INVALID"):
            fail(f"Apple rejected build {number} during processing ({state}); check the email from App Store Connect.")
        time.sleep(30)
    fail(f"Build {number} still not processed after 45 minutes.")


def testflight(number):
    build = wait_build(number)
    existing = call("GET", f"/v1/builds/{build['id']}/betaBuildLocalizations")["data"]
    attributes = {"whatsNew": LISTING["whatToTest"]}
    if existing:
        call("PATCH", f"/v1/betaBuildLocalizations/{existing[0]['id']}",
             {"data": {"type": "betaBuildLocalizations", "id": existing[0]["id"], "attributes": attributes}})
    else:
        call("POST", "/v1/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {**attributes, "locale": LISTING["locale"]},
            "relationships": {"build": ref("builds", build["id"])},
        }})
    print("TestFlight notes set")


def editable_app_info(app):
    for info in call("GET", f"/v1/apps/{app}/appInfos")["data"]:
        if info["attributes"].get("appStoreState", info["attributes"].get("state")) in EDITABLE | {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW"}:
            return info
    fail("No editable app info (is a version already in review?)")


def editable_version(app, version_string, build):
    versions = call("GET", f"/v1/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS"})["data"]
    for version in versions:
        if version["attributes"]["appStoreState"] in EDITABLE:
            if version["attributes"]["versionString"] != version_string:
                call("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {
                    "type": "appStoreVersions", "id": version["id"],
                    "attributes": {"versionString": version_string}}})
            return version
    return call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version_string},
        "relationships": {"app": ref("apps", app), "build": ref("builds", build["id"])},
    }})["data"]


def upsert_localization(collection_path, create_type, parent_key, parent_type, parent_id, attributes):
    existing = [item for item in call("GET", collection_path)["data"] if item["attributes"]["locale"] == LISTING["locale"]]
    if existing:
        call("PATCH", f"/v1/{create_type}/{existing[0]['id']}",
             {"data": {"type": create_type, "id": existing[0]["id"], "attributes": attributes}})
        return existing[0]["id"]
    return call("POST", f"/v1/{create_type}", {"data": {
        "type": create_type,
        "attributes": {**attributes, "locale": LISTING["locale"]},
        "relationships": {parent_key: ref(parent_type, parent_id)},
    }})["data"]["id"]


def upload_screenshots(localization_id):
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")["data"]
    for display_type, files in SCREENSHOTS.items():
        screenshot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display_type), None)
        if screenshot_set is None:
            screenshot_set = call("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": ref("appStoreVersionLocalizations", localization_id)},
            }})["data"]
        # Replace, so re-runs don't stack duplicates.
        for old in call("GET", f"/v1/appScreenshotSets/{screenshot_set['id']}/appScreenshots")["data"]:
            call("DELETE", f"/v1/appScreenshots/{old['id']}")
        for path in files:
            data = path.read_bytes()
            shot = call("POST", "/v1/appScreenshots", {"data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": ref("appScreenshotSets", screenshot_set["id"])},
            }})["data"]
            for operation in shot["attributes"]["uploadOperations"]:
                chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
                headers = {h["name"]: h["value"] for h in operation["requestHeaders"]}
                response = requests.request(operation["method"], operation["url"], headers=headers, data=chunk, timeout=120)
                if response.status_code >= 300:
                    fail(f"Screenshot upload of {path.name} failed: {response.status_code}")
            call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
                "type": "appScreenshots", "id": shot["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
            }})
            print(f"screenshot {path.name} uploaded")


def set_age_rating(app_info):
    declaration = call("GET", f"/v1/appInfos/{app_info['id']}/ageRatingDeclaration")["data"]
    # Every content category "None"/"No": a tone generator with no web access,
    # chat, ads or user content. Only keys Apple's current schema has are sent.
    known = declaration["attributes"]
    attributes = {}
    for key, value in known.items():
        if key in ("kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl"):
            continue
        if isinstance(value, bool) or value is None and key in (
            "gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "userGeneratedContent",
            "advertising", "healthOrWellnessTopics", "parentalControls", "ageAssurance",
        ):
            attributes[key] = False
        elif isinstance(value, str) or value is None:
            attributes[key] = "NONE"
    call("PATCH", f"/v1/ageRatingDeclarations/{declaration['id']}",
         {"data": {"type": "ageRatingDeclarations", "id": declaration["id"], "attributes": attributes}})
    print("age rating set")


def set_free_price(app):
    if call("GET", f"/v1/apps/{app}/appPriceSchedule", ok=(200, 404)).get("data"):
        return
    points = call("GET", f"/v1/apps/{app}/appPricePoints", params={"filter[territory]": "USA", "limit": 200})["data"]
    free = next(p for p in points if float(p["attributes"]["customerPrice"]) == 0)
    call("POST", "/v1/appPriceSchedules", {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": ref("apps", app),
                "baseTerritory": ref("territories", "USA"),
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]},
            },
        },
        "included": [{
            "type": "appPrices", "id": "${free}",
            "attributes": {"startDate": None},
            "relationships": {"appPricePoint": ref("appPricePoints", free["id"])},
        }],
    })
    print("price set to free")


def set_review_details(version):
    contact = {
        "contactFirstName": os.environ.get("ASC_CONTACT_FIRST_NAME", ""),
        "contactLastName": os.environ.get("ASC_CONTACT_LAST_NAME", ""),
        "contactEmail": os.environ.get("ASC_CONTACT_EMAIL", ""),
        "contactPhone": os.environ.get("ASC_CONTACT_PHONE", ""),
    }
    attributes = {**{k: v for k, v in contact.items() if v}, "demoAccountRequired": False, "notes": LISTING["reviewNotes"]}
    existing = call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail", ok=(200, 404)).get("data")
    if existing:
        call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}",
             {"data": {"type": "appStoreReviewDetails", "id": existing["id"], "attributes": attributes}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attributes,
            "relationships": {"appStoreVersion": ref("appStoreVersions", version["id"])},
        }})
    missing = [k for k, v in contact.items() if not v]
    if missing:
        print(f"::warning::App Review contact incomplete ({', '.join(missing)}); set the ASC_CONTACT_* variables before submitting.")


def listing(number):
    app = app_id()
    build = wait_build(number)
    version_string = os.environ.get("MARKETING_VERSION", "1.0")

    call("PATCH", f"/v1/apps/{app}", {"data": {"type": "apps", "id": app,
         "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})

    info = editable_app_info(app)
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": ref("appCategories", LISTING["primaryCategory"]),
        "secondaryCategory": ref("appCategories", LISTING["secondaryCategory"]),
    }}})
    upsert_localization(f"/v1/appInfos/{info['id']}/appInfoLocalizations", "appInfoLocalizations", "appInfo", "appInfos",
                        info["id"], {"name": LISTING["name"], "subtitle": LISTING["subtitle"],
                                     "privacyPolicyUrl": LISTING["privacyPolicyUrl"]})
    set_age_rating(info)
    set_free_price(app)

    version = editable_version(app, version_string, build)
    call("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"],
        "attributes": {"copyright": LISTING["copyright"], "releaseType": "AFTER_APPROVAL"},
        "relationships": {"build": ref("builds", build["id"])},
    }})
    localization = upsert_localization(
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", "appStoreVersionLocalizations",
        "appStoreVersion", "appStoreVersions", version["id"],
        {k: LISTING[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")},
    )
    upload_screenshots(localization)
    set_review_details(version)
    print(f"listing for {version_string} ({number}) is ready")


def submit():
    app = app_id()
    versions = call("GET", f"/v1/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS"})["data"]
    version = next((v for v in versions if v["attributes"]["appStoreState"] in EDITABLE), None)
    if version is None:
        fail("No version waiting to be submitted (already in review or released?)")
    submission = call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": ref("apps", app)}}})["data"]
    call("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": ref("reviewSubmissions", submission["id"]),
                          "appStoreVersion": ref("appStoreVersions", version["id"])}}})
    call("PATCH", f"/v1/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print(f"version {version['attributes']['versionString']} submitted for App Review")


if __name__ == "__main__":
    command, *args = sys.argv[1:] or ["help"]
    if command == "wait-build":
        wait_build(int(args[0]))
    elif command == "testflight":
        testflight(int(args[0]))
    elif command == "listing":
        listing(int(args[0]))
    elif command == "submit":
        submit()
    else:
        print(__doc__)
        sys.exit(2)
