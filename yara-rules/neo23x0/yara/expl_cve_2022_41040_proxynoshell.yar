
rule EXPL_Exchange_ProxyNoShell_Patterns_CVE_2022_41040_Oct22_1 : SCRIPT {
   meta:
      description = "Detects successful ProxyNoShell exploitation attempts in log files (attempt to identify the attack before the official release of detailed information)"
      author = "Florian Roth"
      score = 75
      reference = "https://github.com/kljunowsky/CVE-2022-41040-POC"
      date = "2022-10-11"
   strings:
      $sr1 = / \/autodiscover\/autodiscover\.json[^\n]{1,300}owershell/ nocase ascii

      $sa1 = " 200 "
      $sa2 = " 401 "

      $fp1 = " 444 "
      $fp2 = " 404 "
      $fp3 = "GET /owa/ &Email=autodiscover/autodiscover.json%3F@test.com&ClientId=" ascii /* Nessus */
      $fp4 = "@test.com/owa/?&Email=autodiscover/autodiscover.json%3F@test.com" ascii /* Nessus */
   condition:
      $sr1 
      and 1 of ($sa*)
      and not 1 of ($fp*)
}
