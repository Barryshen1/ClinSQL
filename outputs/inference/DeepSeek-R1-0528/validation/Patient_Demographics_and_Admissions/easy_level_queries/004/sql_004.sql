WITH first_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
    SELECT subject_id, MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) first 
    ON a.subject_id = first.subject_id 
    AND a.admittime = first.first_admittime
  WHERE a.dischtime >= a.admittime  -- Ensure valid LOS
),
aki_cohort AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.hadm_id = fa.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '584%') 
          OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
        )
    )
),
los_calculations AS (
  SELECT 
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM aki_cohort
)
SELECT 
  STDDEV_SAMP(los_days) AS sd_length_of_stay_days
FROM los_calculations;