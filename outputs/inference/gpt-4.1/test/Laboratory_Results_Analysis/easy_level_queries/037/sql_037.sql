WITH sepsis_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    -- ICD-9 sepsis codes
    (d.icd_version = 9 AND (
      d.icd_code IN ('99591','99592','99593','99594','78552','99932','77181','7907')
      OR d.icd_code LIKE '038%'
    ))
    -- ICD-10 sepsis codes
    OR (d.icd_version = 10 AND (
      d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%'
    ))
  )
),
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
sepsis_male_admissions AS (
  SELECT sa.subject_id, sa.hadm_id
  FROM sepsis_admissions sa
  INNER JOIN male_patients mp ON sa.subject_id = mp.subject_id
),
platelet_labs AS (
  SELECT l.subject_id, l.hadm_id, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 51265 -- Platelet Count
    AND l.valuenum IS NOT NULL
),
peak_platelet_per_admission AS (
  SELECT sma.subject_id, sma.hadm_id, MAX(pl.valuenum) AS peak_platelet
  FROM sepsis_male_admissions sma
  INNER JOIN platelet_labs pl
    ON sma.subject_id = pl.subject_id AND sma.hadm_id = pl.hadm_id
  GROUP BY sma.subject_id, sma.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_platelet, 4)[OFFSET(3)] AS percentile_75_peak_platelet
FROM peak_platelet_per_admission;