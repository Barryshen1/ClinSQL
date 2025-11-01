WITH patient_data AS (
  SELECT a.hadm_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age = 61
),
creatinine_nadir AS (
  SELECT l.hadm_id, MIN(l.valuenum) AS nadir
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50813
  GROUP BY l.hadm_id
)
SELECT 
  APPROX_QUANTILES(c.nadir, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(c.nadir, 100)[OFFSET(75)] AS q3
FROM creatinine_nadir c
INNER JOIN patient_data d ON c.hadm_id = d.hadm_id;