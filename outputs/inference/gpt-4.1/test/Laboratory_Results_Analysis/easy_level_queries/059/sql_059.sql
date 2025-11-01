WITH sepsis_icd_codes AS (
  -- List of ICD codes for sepsis (ICD-9 and ICD-10)
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT '78552', 9 UNION ALL
  SELECT '038', 9 UNION ALL
  SELECT 'A40', 10 UNION ALL
  SELECT 'A41', 10
),
sepsis_admissions AS (
  -- Find admissions for 93-year-old males with sepsis
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN sepsis_icd_codes sicd
    ON diag.icd_version = sicd.icd_version
    -- Match full code or prefix (for codes like 038.*, A40.*, A41.*)
    AND (diag.icd_code = sicd.icd_code OR diag.icd_code LIKE CONCAT(sicd.icd_code, '%'))
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 93
),
platelet_itemids AS (
  -- Find itemids for platelet count
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
),
platelet_on_discharge AS (
  -- Get platelet counts on discharge day for qualifying admissions
  SELECT
    la.subject_id,
    la.hadm_id,
    la.charttime,
    la.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` la
  JOIN sepsis_admissions sa
    ON la.subject_id = sa.subject_id
    AND la.hadm_id = sa.hadm_id
  JOIN platelet_itemids pi
    ON la.itemid = pi.itemid
  WHERE DATE(la.charttime) = DATE(sa.dischtime)
    AND la.valuenum IS NOT NULL
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS platelet_75th_percentile
FROM platelet_on_discharge
;