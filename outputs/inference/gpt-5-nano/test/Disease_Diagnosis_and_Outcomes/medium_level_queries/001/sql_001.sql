WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    -- LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    -- Day-1 ICU status: overlap with ICU stay within first 24 hours
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_icu.icustays icu
        WHERE icu.subject_id = a.subject_id
          AND icu.hadm_id = a.hadm_id
          AND icu.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
          AND icu.outtime >= a.admittime
      ) THEN 1 ELSE 0
    END AS day1_icu,
    -- Has CKD (CKD phenotype in long_title)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
        JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
          ON di.icd_code = dd.icd_code
         AND di.icd_version = dd.icd_version
        WHERE di.subject_id = a.subject_id
          AND di.hadm_id = a.hadm_id
          AND (LOWER(dd.long_title) LIKE '%chronic kidney disease%'
               OR LOWER(dd.long_title) LIKE '%kidney disease%')
      ) THEN 1 ELSE 0
    END AS has_ckd,
    -- Has diabetes
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
        JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
          ON di.icd_code = dd.icd_code
         AND di.icd_version = dd.icd_version
        WHERE di.subject_id = a.subject_id
          AND di.hadm_id = a.hadm_id
          AND LOWER(dd.long_title) LIKE '%diabetes%'
      ) THEN 1 ELSE 0
    END AS has_diabetes
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS p
      ON a.subject_id = p.subject_id
  WHERE
    -- Gender: male
    (LOWER(p.gender) = 'm' OR p.gender = 'M')
    -- Age 67-77 at admission
    AND (CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    -- Have a discharge (to compute LOS)
    AND a.dischtime IS NOT NULL
    -- ADHF diagnosis exists for this admission
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (LOWER(dd.long_title) LIKE '%heart failure%')
    )
)
SELECT
  CASE
    WHEN los_days <= 7.0 THEN '≤7'
    ELSE '>7'
  END AS los_group,
  day1_icu AS day1_icu_status,
  COUNT(*) AS n,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_percent,
  100.0 * AVG(has_ckd) AS ckd_prev,
  100.0 * AVG(has_diabetes) AS diabetes_prev
FROM cohort
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;