WITH cohort AS (
  SELECT 
      a.hadm_id,
      DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE 
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
      AND a.hadm_id IN (
          -- Admissions with Heart Failure
          SELECT hadm_id
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          WHERE 
              (icd_version = 9 AND icd_code LIKE '428%') 
              OR (icd_version = 10 AND icd_code LIKE 'I50%')
          INTERSECT DISTINCT
          -- Admissions with COPD
          SELECT hadm_id
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          WHERE 
              (icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '496%'))
              OR (icd_version = 10 AND icd_code LIKE 'J44%')
      )
)
SELECT 
  STDDEV_POP(los_days) AS sd_length_of_stay_days
FROM cohort;