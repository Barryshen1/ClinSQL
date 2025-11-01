WITH first_admission AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
    SELECT 
      subject_id, 
      MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) fa 
    ON a.subject_id = fa.subject_id 
    AND a.admittime = fa.first_admittime
),
cohort AS (
  SELECT 
    fa.subject_id, 
    fa.hadm_id,
    DATETIME_DIFF(fa.dischtime, fa.admittime, SECOND) / 86400.0 AS los_days
  FROM first_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
      WHERE 
        rx.subject_id = fa.subject_id 
        AND rx.hadm_id = fa.hadm_id
        AND (
          LOWER(rx.drug) LIKE '%warfarin%' 
          OR LOWER(rx.drug) LIKE '%heparin%' 
          OR LOWER(rx.drug) LIKE '%enoxaparin%' 
          OR LOWER(rx.drug) LIKE '%rivaroxaban%' 
          OR LOWER(rx.drug) LIKE '%apixaban%' 
          OR LOWER(rx.drug) LIKE '%dabigatran%'
        )
    )
)
SELECT 
  STDDEV(los_days) AS sd_length_of_stay_days
FROM cohort;