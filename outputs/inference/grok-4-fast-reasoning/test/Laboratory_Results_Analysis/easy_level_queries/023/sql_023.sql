WITH cohort AS (
  SELECT DISTINCT a.hadm_id, DATE(a.dischtime) AS discharge_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE p.gender = 'M'
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'A40.%' 
         OR d.icd_code LIKE 'A41.%' 
         OR d.icd_code LIKE 'R65.2%')
),
lactate_measurements AS (
  SELECT l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c 
    ON l.hadm_id = c.hadm_id
  WHERE DATE(l.charttime) = c.discharge_date
    AND l.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
      WHERE label = 'Lactate' AND category = 'Chemistry'
    )
    AND l.valuenum IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr_lactate
FROM lactate_measurements;