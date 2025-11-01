WITH aki_primary AS (
  -- Identify admissions with primary AKI (AKI as the first/primary diagnosis)
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE di.seq_num = 1
    AND (LOWER(d.long_title) LIKE '%acute kidney%' OR LOWER(d.long_title) LIKE '%acute renal%')
),
age_filtered AS (
  -- Join admissions with patients to apply gender and age criteria
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         FLOOR(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM aki_primary ak
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = ak.subject_id
   AND a.hadm_id = ak.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) = 'm'
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS p75_los_days
FROM age_filtered
WHERE age_at_admit BETWEEN 37 AND 47
LIMIT 1;