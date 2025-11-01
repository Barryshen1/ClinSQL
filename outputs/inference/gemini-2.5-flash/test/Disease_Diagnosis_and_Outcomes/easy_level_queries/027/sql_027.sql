with hemorrhage
            d.icd_code LIKE '534%' OR -- Gastrojejunal ulcer with hemorrhage
            d.icd_code = '53021' OR -- Ulcer of esophagus with hemorrhage
            d.icd_code = '5780' OR  -- Hematemesis
            d.icd_code = '5781' OR  -- Melena
            d.icd_code LIKE '4560%' OR -- Esophageal varices with bleeding
            d.icd_code LIKE '4562%'    -- Esophageal varices with bleeding in other diseases (e.g., 45620, 45621)
        ))
        OR
        -- ICD-10 codes for Upper GI bleed (common codes for hemorrhage involving upper GI tract)
        (d.icd_version = 10 AND (
            d.icd_code LIKE 'K227%' OR -- Gastroesophageal laceration-hemorrhage syndrome (Mallory-Weiss)
            d.icd_code LIKE 'K25%' OR -- Gastric ulcer with hemorrhage
            d.icd_code LIKE 'K26%' OR -- Duodenal ulcer with hemorrhage
            d.icd_code LIKE 'K27%' OR -- Peptic ulcer, unspecified, with hemorrhage
            d.icd_code LIKE 'K28%' OR -- Gastrojejunal ulcer with hemorrhage
            d.icd_code = 'K920' OR  -- Hematemesis
            d.icd_code = 'K921' OR  -- Melena
            d.icd_code LIKE 'I850%'    -- Esophageal varices with bleeding (e.g., I8500, I8501)
        ))
    );