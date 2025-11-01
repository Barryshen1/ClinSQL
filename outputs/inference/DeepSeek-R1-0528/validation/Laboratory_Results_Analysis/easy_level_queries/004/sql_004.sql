WITH sepsis_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) = 76
    AND (
      (diag.icd_version = 9 AND (diag.icd_code LIKE '038%' OR diag.icd_code IN ('99591', '99592', '78552')))
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R65%'))
    )
),
platelet_avg_per_admission AS (
  SELECT
    sa.hadm_id,
    AVG(le.valuenum) AS avg_platelet
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.subject_id = le.subject_id
    AND sa.hadm_id = le.hadm_id
  WHERE
    le.itemid = 51265  -- Platelet count
    AND le.charttime BETWEEN sa.admittime AND DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY sa.hadm_id
)
SELECT
  APPROX_QUANTILES(avg_platelet, 100)[OFFSET(50)] AS median_platelet
FROM platelet_avg_per_admission;