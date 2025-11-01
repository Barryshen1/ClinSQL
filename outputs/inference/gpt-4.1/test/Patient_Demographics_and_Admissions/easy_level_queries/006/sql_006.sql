WITH sepsis_icd_codes AS (
  -- List of ICD codes for sepsis (ICD-9 and ICD-10)
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT '78552', 9 UNION ALL
  SELECT 'A40', 10 UNION ALL
  SELECT 'A41', 10
),
sepsis_admissions AS (
  -- Find admissions with any sepsis code
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN sepsis_icd_codes s
    ON d.icd_version = s.icd_version
   AND (
     -- For ICD-10, match prefix (A40*, A41*)
     (s.icd_version = 10 AND LEFT(d.icd_code, 3) IN ('A40', 'A41'))
     -- For ICD-9, match exact code
     OR (s.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
   )
)
SELECT
  APPROX_QUANTILES(i.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN sepsis_admissions sa
  ON a.subject_id = sa.subject_id AND a.hadm_id = sa.hadm_id
JOIN physionet-data.mimiciv_3_1_icu.icustays i
  ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 58 AND 68;