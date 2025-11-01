WITH sepsis_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R65.20'))
    OR
    (icd_version = 9 AND icd_code LIKE '038%')
  )
  AND hadm_id IS NOT NULL
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '<=3'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 6 THEN '4-6'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 10 THEN '7-10'
      ELSE '>10'
    END AS los_cat,
    CASE 
      WHEN a.hospital_expire_flag = 1 
      THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) 
    END AS days_to_death,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = a.subject_id 
          AND i.hadm_id = a.hadm_id
          AND i.intime >= a.admittime
          AND i.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      ) THEN 'Yes' 
      ELSE 'No' 
    END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN sepsis_hadm s 
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.dischtime > a.admittime
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE NOT EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE di.subject_id = cohort.subject_id
      AND di.hadm_id = cohort.hadm_id
      AND di.icd_code IN ('R65.21', '785.52')
  )
)
SELECT 
  los_cat,
  icu_day1,
  COUNT(*) AS n,
  COUNTIF(hospital_expire_flag = 1) AS n_deaths,
  SAFE_DIVIDE(COUNTIF(hospital_expire_flag = 1), COUNT(*)) * 100 AS mortality_pct,
  PERCENTILE_CONT(days_to_death, 0.5) AS median_days_to_death
FROM filtered_cohort
GROUP BY los_cat, icu_day1
ORDER BY 
  CASE los_cat 
    WHEN '<=3' THEN 1 
    WHEN '4-6' THEN 2 
    WHEN '7-10' THEN 3 
    ELSE 4 
  END,
  CASE icu_day1 WHEN 'No' THEN 1 ELSE 2 END;