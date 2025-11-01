with acute/chronic hemorrhage
                OR REGEXP_LIKE(diag.icd_code, '^K26\\.[0246]$') -- Duodenal ulcer with acute/chronic hemorrhage
                OR REGEXP_LIKE(diag.icd_code, '^K27\\.[0246]$') -- Peptic ulcer, site unspecified, with acute/chronic hemorrhage
                OR (diag.icd_code LIKE 'K29._1') -- Gastritis/duodenitis with hemorrhage (e.g., K29.01, K29.21, etc.)
                OR diag.icd_code IN ('K92.0', -- Hematemesis
                                      'K92.1', -- Melena
                                      'I85.01', -- Esophageal varices with bleeding
                                      'K22.6') -- Mallory-Weiss syndrome with hemorrhage
            )
    )
LIMIT 1;