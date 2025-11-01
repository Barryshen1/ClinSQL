WITH sepsis_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code LIKE '038%') OR
    (icd_version = 10 AND (
      icd_code LIKE 'A40%' OR
      icd_code LIKE 'A41%' OR
      icd_code LIKE 'R65.2%'
    ))
  )
),
male_sepsis_patients AS (
  SELECT s.subject_id
  FROM sepsis_hadms s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
peak_platelets AS (
  SELECT msp.subject_id, MAX(le.valuenum) AS peak
  FROM male_sepsis_patients msp
  INNER JOIN sepsis_hadms sh
    ON msp.subject_id = sh.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sh.hadm_id = le.hadm_id
    AND le.itemid = 51265
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY msp.subject_id
)
SELECT PERCENTILE_CONT(peak, 0.75) AS p75_peak_platelets
FROM peak_platelets;