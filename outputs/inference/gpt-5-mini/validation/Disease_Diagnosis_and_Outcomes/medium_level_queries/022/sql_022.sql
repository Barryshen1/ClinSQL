WITH diag_text_flags AS (
  -- For each hospital admission, flag whether any diagnosis mentions sepsis
  -- and whether any diagnosis mentions septic shock (case-insensitive).
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%' OR LOWER(dd.long_title) LIKE '%septicemia%' THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  USING (icd_code, icd_version)
  GROUP BY d.hadm_id
),

cohort AS (
  -- Admissions for male patients aged 50-60 that have sepsis (by text) but not septic shock
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    diag_text_flags dt
    ON a.hadm_id = dt.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND dt.has_sepsis = 1
    AND dt.has_septic_shock = 0
),

cohort_with_icu AS (
  -- Attach a boolean indicating whether the admission had any ICU stay overlapping hospital day 1
  SELECT
    c.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
      WHERE ic.hadm_id = c.hadm_id
        -- ICU stay starts before the end of hospital day 1 and continues past admission start
        AND ic.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
        AND ic.outtime > c.admittime
    ) THEN TRUE ELSE FALSE END AS icu_day1
  FROM cohort c
)

SELECT
  CASE WHEN los_days <= 7 THEN '<=7 days' ELSE '>7 days' END AS los_bucket,
  CASE WHEN icu_day1 THEN 'ICU on day 1' ELSE 'No ICU on day 1' END AS day1_icu_status,
  COUNT(*) AS admissions_n,
  SUM(hospital_expire_flag) AS deaths_n,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS in_hospital_mortality_pct,
  -- approximate median LOS in days
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM
  cohort_with_icu
GROUP BY
  los_bucket,
  day1_icu_status
ORDER BY
  los_bucket,
  day1_icu_status;