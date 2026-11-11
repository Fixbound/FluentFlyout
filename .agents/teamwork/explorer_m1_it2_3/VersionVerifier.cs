using System;

namespace ExplorerM1It2Test
{
    public static class VersionVerifier
    {
        public static bool IsNewerVersion(string currentVersion, string newestVersion)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(newestVersion)) return false;

                string cleanCurrent = CleanVersionString(currentVersion);
                string cleanNewest = CleanVersionString(newestVersion);

                if (NormalizeVersion(cleanCurrent, out var current) && NormalizeVersion(cleanNewest, out var newest))
                {
                    if (newest > current) return true;
                    if (newest < current) return false;

                    // Base versions are identical (e.g. 2.16.0 vs 2.16.0.0 or 2.16.0-beta.1 vs 2.16.0)
                    string preCurrent = ExtractPrerelease(currentVersion);
                    string preNewest = ExtractPrerelease(newestVersion);

                    bool currentHasPre = !string.IsNullOrEmpty(preCurrent);
                    bool newestHasPre = !string.IsNullOrEmpty(preNewest);

                    // Case 1: Current is prerelease and newest is stable release of same base -> upgrade
                    if (currentHasPre && !newestHasPre) return true;

                    // Case 2: Current is stable and newest is prerelease of same base -> not an upgrade
                    if (!currentHasPre && newestHasPre) return false;

                    // Case 3: Both are prereleases of same base -> compare prerelease tags
                    if (currentHasPre && newestHasPre)
                    {
                        return ComparePrerelease(preCurrent, preNewest) < 0;
                    }

                    // Case 4: Both are stable releases and identical (e.g. 2.16.0 vs 2.16.0.0) -> not an upgrade
                    return false;
                }
                return false;
            }
            catch (Exception)
            {
                return false;
            }
        }

        public static string CleanVersionString(string version)
        {
            if (string.IsNullOrWhiteSpace(version)) return "0.0.0.0";
            var v = version.Trim().TrimStart('v', 'V').Trim();
            var splitIndex = v.IndexOfAny(['-', '+']);
            if (splitIndex >= 0)
            {
                v = v[..splitIndex];
            }
            return v;
        }

        public static string ExtractPrerelease(string version)
        {
            if (string.IsNullOrWhiteSpace(version)) return string.Empty;
            var v = version.Trim().TrimStart('v', 'V').Trim();
            var dashIndex = v.IndexOf('-');
            if (dashIndex < 0) return string.Empty;
            var pre = v[(dashIndex + 1)..];
            var plusIndex = pre.IndexOf('+');
            if (plusIndex >= 0)
            {
                pre = pre[..plusIndex];
            }
            return pre.Trim();
        }

        public static int ComparePrerelease(string preA, string preB)
        {
            if (string.Equals(preA, preB, StringComparison.OrdinalIgnoreCase))
                return 0;

            var partsA = preA.Split('.');
            var partsB = preB.Split('.');
            int minLen = Math.Min(partsA.Length, partsB.Length);

            for (int i = 0; i < minLen; i++)
            {
                string a = partsA[i];
                string b = partsB[i];

                if (string.Equals(a, b, StringComparison.OrdinalIgnoreCase))
                    continue;

                bool isNumA = long.TryParse(a, out long numA);
                bool isNumB = long.TryParse(b, out long numB);

                if (isNumA && isNumB)
                {
                    int cmpNum = numA.CompareTo(numB);
                    if (cmpNum != 0) return cmpNum;
                    continue;
                }

                if (isNumA && !isNumB)
                {
                    // SemVer 2.0 §11.4: Numeric identifiers have lower precedence than non-numeric identifiers
                    return -1;
                }

                if (!isNumA && isNumB)
                {
                    return 1;
                }

                int cmpStr = string.Compare(a, b, StringComparison.OrdinalIgnoreCase);
                if (cmpStr != 0) return cmpStr;
            }

            return partsA.Length.CompareTo(partsB.Length);
        }

        public static bool NormalizeVersion(string cleaned, out Version version)
        {
            version = new Version(0, 0, 0, 0);
            if (string.IsNullOrWhiteSpace(cleaned)) return false;

            var parts = cleaned.Split('.');
            if (parts.Length == 0 || parts.Length > 4) return false;

            int major = 0, minor = 0, build = 0, rev = 0;

            if (parts.Length > 0 && (!int.TryParse(parts[0], out major) || major < 0)) return false;
            if (parts.Length > 1 && (!int.TryParse(parts[1], out minor) || minor < 0)) return false;
            if (parts.Length > 2 && (!int.TryParse(parts[2], out build) || build < 0)) return false;
            if (parts.Length > 3 && (!int.TryParse(parts[3], out rev) || rev < 0)) return false;

            version = new Version(major, minor, build, rev);
            return true;
        }
    }
}
