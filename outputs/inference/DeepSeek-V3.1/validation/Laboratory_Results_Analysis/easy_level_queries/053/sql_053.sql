WITH stroke_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pt.anchor_age = 82
    AND pt.gender = 'F'
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '433%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '434%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '436%')
    )
),
first_glucose AS (
  SELECT sa.hadm_id, MIN(le.charttime) AS first_charttime
  FROM stroke_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  WHERE le.itemid IN (50809, 50931)  -- Serum glucose itemids
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND le.charttime BETWEEN sa.admittime AND DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
  GROUP BY sa.hadm_id
),
glucose_values AS (
  SELECT le.valuenum AS glucose_value
  FROM first_glucose fg
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fg.hadm_id = le.hadm_id
      AND fg.first_charttime = le.charttime
      AND le.itemid IN (50809, 50931)
      AND le.valuenum IS NOT NULL
      AND le.valueuom = 'mg/dL'
)
SELECT
  PERCENTILE_CONT(glucose_value, 0.75) OVER() AS percentile_75
FROM glucose_values
LIMIT 1;