WITH septic_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 1
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND dd.long_title LIKE '%sepsis%'
        AND dd.long_title NOT LIKE '% septic shock %'
    )
),
icu_flags AS (
  SELECT
    sc.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = sc.subject_id
          AND i.hadm_id = sc.hadm_id
          AND i.intime <= TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
          AND i.outtime > sc.admittime
      ) THEN 1 ELSE 0
    END AS icu_day1_flag
  FROM septic_cohort sc
)

SELECT
  CASE
    WHEN hosp_los_days <= 3 THEN '<=3'
    WHEN hosp_los_days BETWEEN 4 AND 6 THEN '4-6'
    WHEN hosp_los_days BETWEEN 7 AND 10 THEN '7-10'
    ELSE '>10'
  END AS los_group,
  icu_day1_flag,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths_in_hospital,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_percent,
  APPROX_MEDIAN(CASE WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(deathtime, admittime, DAY) END) AS median_days_to_death
FROM icu_flags
GROUP BY los_group, icu_day1_flag
ORDER BY los_group, icu_day1_flag;