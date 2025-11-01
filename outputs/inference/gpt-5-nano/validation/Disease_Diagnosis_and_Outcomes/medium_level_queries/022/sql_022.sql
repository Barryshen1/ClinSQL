WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS hospital_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) IN ('m','male')
    AND p.anchor_age BETWEEN 50 AND 60
    -- Sepsis: presence of sepsis/septicemia diagnosis (ICD-9/ICD-10)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%sepsis%'
          OR LOWER(dd.long_title) LIKE '%septicemia%'
          OR di.icd_code LIKE 'A41%'      -- ICD-10 sepsis
          OR di.icd_code LIKE '038%'       -- ICD-9 septicemia
        )
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (
          LOWER(dd2.long_title) LIKE '%septic shock%'
          OR di2.icd_code LIKE '785.52%'      -- ICD-9 septic shock
        )
    )
),
day1_flag AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
        WHERE ic.subject_id = c.subject_id
          AND ic.hadm_id = c.hadm_id
          AND ic.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
          AND ic.outtime > c.admittime
      ) THEN 'Yes'
      ELSE 'No'
    END AS day1_in_icu,
    c.hospital_expire_flag,
    c.hospital_los_days
  FROM cohort c
)
SELECT
  day1_in_icu AS day1_icu_status,
  CASE WHEN hospital_los_days <= 7 THEN '≤7' ELSE '>7' END AS los_group,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  APPROX_QUANTILES(hospital_los_days, 101)[OFFSET(50)] AS median_los_days
FROM day1_flag
GROUP BY day1_in_icu, los_group
ORDER BY day1_in_icu, los_group;