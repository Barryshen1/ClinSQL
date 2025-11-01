WITH cohort AS (
  SELECT 
      a.hadm_id,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE 
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
          WHERE 
              di.hadm_id = a.hadm_id 
              AND (
                  (di.icd_version = 9 AND di.icd_code BETWEEN '430' AND '432') 
                  OR 
                  (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I6[0-2]'))
              )
      )
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
          WHERE 
              di.hadm_id = a.hadm_id 
              AND (
                  (di.icd_version = 9 AND di.icd_code = '491.21') 
                  OR 
                  (di.icd_version = 10 AND di.icd_code = 'J44.1')
              )
      )
      AND a.dischtime >= a.admittime  -- Ensure valid LOS
)
SELECT 
    quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM (
    SELECT APPROX_QUANTILES(los_days, 4) AS quantiles 
    FROM cohort
);