WITH eligible AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 42 AND 52
    AND LOWER(p.gender) IN ('male', 'm')
    AND a.dischtime IS NOT NULL
    -- Diabetes diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- Acute HF diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%acute%'
        AND LOWER(dd2.long_title) LIKE '%heart failure%'
    )
),

booleans AS (
  SELECT e.hadm_id,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'INSULIN')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS insulin_first24,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'METFORMIN')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS metformin_first24,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'GLYBURIDE|GLIPIZIDE|GLIMEPIRIDE')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS sulfonylurea_first24,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'SITAGLIP|SITAGLIPTIN|DPP')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS dpp4_first24,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'SGLT2|FLOZIN|CANAGLIFLOZIN|DAPAGLIFLOZIN|EMPA|DAPA')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS sglt2_first24,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'GLP-?1|GLP1|EXENATIDE|LIRAGLUTIDE|DULAGLUTIDE|ALBIGLUTIDE')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS glp1_first24,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'PIOGLITAZONE|ROSIGLITAZONE')
                    AND p.starttime <= TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
                    AND (p.stoptime IS NULL OR p.stoptime >= e.admittime)
               THEN 1 ELSE 0 END) AS tzd_first24,

         -- final 12h booleans
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'INSULIN')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS insulin_final12,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'METFORMIN')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS metformin_final12,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'GLYBURIDE|GLIPIZIDE|GLIMEPIRIDE')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS sulfonylurea_final12,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'SITAGLIP|SITAGLIPTIN|DPP')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS dpp4_final12,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'SGLT2|FLOZIN|CANAGLIFLOZIN|DAPAGLIFLOZIN|EMPA|DAPA')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS sglt2_final12,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'GLP-?1|GLP1|EXENATIDE|LIRAGLUTIDE|DULAGLUTIDE|ALBIGLUTIDE')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS glp1_final12,
         MAX(CASE
               WHEN REGEXP_CONTAINS(UPPER(p.drug), 'PIOGLITAZONE|ROSIGLITAZONE')
                    AND p.starttime <= e.dischtime
                    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR))
               THEN 1 ELSE 0 END) AS tzd_final12
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.subject_id = e.subject_id
   AND p.hadm_id = e.hadm_id
  GROUP BY e.hadm_id
)

SELECT class,
       100.0 * SUM(first24) / COUNT(*) AS prevalence_first24,
       100.0 * SUM(final12) / COUNT(*) AS prevalence_final12,
       (100.0 * SUM(final12) / COUNT(*) - 100.0 * SUM(first24) / COUNT(*)) AS net_change_pp
FROM (
  SELECT hadm_id, 'Insulin' AS class, insulin_first24 AS first24, insulin_final12 AS final12 FROM booleans
  UNION ALL
  SELECT hadm_id, 'Metformin' AS class, metformin_first24,       metformin_final12 FROM booleans
  UNION ALL
  SELECT hadm_id, 'Sulfonylurea' AS class, sulfonylurea_first24,  sulfonylurea_final12 FROM booleans
  UNION ALL
  SELECT hadm_id, 'DPP-4' AS class, dpp4_first24,               dpp4_final12 FROM booleans
  UNION ALL
  SELECT hadm_id, 'SGLT2' AS class, sglt2_first24,               sglt2_final12 FROM booleans
  UNION ALL
  SELECT hadm_id, 'GLP-1' AS class, glp1_first24,                 glp1_final12 FROM booleans
  UNION ALL
  SELECT hadm_id, 'TZD' AS class, tzd_first24,                   tzd_final12 FROM booleans
) AS x
GROUP BY class
ORDER BY class;