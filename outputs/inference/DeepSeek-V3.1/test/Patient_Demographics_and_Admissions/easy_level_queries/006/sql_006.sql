WITH sepsis_codes AS (
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT '78552', 9 UNION ALL
  SELECT 'A41', 10 UNION ALL
  SELECT 'R65.20', 10 UNION ALL
  SELECT 'R65.21', 10
)

SELECT
  APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON icu.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON icu.hadm_id = diag.hadm_id
INNER JOIN sepsis_codes sc
  ON diag.icd_code = sc.icd_code AND diag.icd_version = sc.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 58 AND 68;