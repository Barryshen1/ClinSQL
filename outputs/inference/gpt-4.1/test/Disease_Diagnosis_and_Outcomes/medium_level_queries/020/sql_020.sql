WITH sepsis_admissions AS (
  -- Identify male patients aged 86-96 with sepsis (excluding septic shock)
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    -- Sepsis diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
      WHERE
        (
          -- ICD-10 sepsis codes
          (dx.icd_version = 10 AND (
            REGEXP_CONTAINS(dx.icd_code, r'^A40') OR
            REGEXP_CONTAINS(dx.icd_code, r'^A41')
          ))
          OR
          -- ICD-9 sepsis codes
          (dx.icd_version = 9 AND (
            dx.icd_code IN ('99591', '99592')
          ))
        )
        -- Exclude septic shock
        AND NOT (
          (dx.icd_version = 10 AND dx.icd_code = 'R6521') OR
          (dx.icd_version = 9 AND dx.icd_code = '78552')
        )
    ) sepsis_dx
      ON adm.hadm_id = sepsis_dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 86 AND 96
    -- Exclude admissions with missing times
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
icu_day1_status AS (
  -- For each admission, determine if patient was in ICU on day 1
  SELECT
    sa.subject_id,
    sa.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE
          icu.hadm_id = sa.hadm_id
          AND icu.intime < sa.admittime + INTERVAL 1 DAY
          AND icu.outtime > sa.admittime
      ) THEN 'ICU on day 1'
      ELSE 'No ICU day 1'
    END AS icu_day1_status,
    sa.admittime,
    sa.dischtime,
    sa.deathtime,
    sa.hospital_expire_flag
  FROM sepsis_admissions sa
),
los_binned AS (
  -- Calculate LOS bins
  SELECT
    *,
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 3 THEN '≤3'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 6 THEN '4–6'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 7 AND 10 THEN '7–10'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) > 10 THEN '>10'
      ELSE 'Unknown'
    END AS los_bin
  FROM icu_day1_status
),
mortality_stats AS (
  -- For each group, calculate mortality and median days-to-death
  SELECT
    los_bin,
    icu_day1_status,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_percent,
    -- Median days-to-death among those who died in hospital
    APPROX_QUANTILES(
      CASE
        WHEN hospital_expire_flag = 1 THEN
          -- Use deathtime if available, else dischtime
          SAFE_CAST(TIMESTAMP_DIFF(
            COALESCE(deathtime, dischtime),
            admittime,
            DAY
          ) AS INT64)
        ELSE NULL
      END,
      2
    )[OFFSET(1)] AS median_days_to_death
  FROM los_binned
  WHERE los_bin != 'Unknown'
  GROUP BY los_bin, icu_day1_status
  ORDER BY
    -- Custom order for bins
    CASE los_bin
      WHEN '≤3' THEN 1
      WHEN '4–6' THEN 2
      WHEN '7–10' THEN 3
      WHEN '>10' THEN 4
      ELSE 5
    END,
    icu_day1_status
)

SELECT
  los_bin AS hospital_LOS_bin,
  icu_day1_status,
  n_admissions,
  n_deaths,
  mortality_percent,
  median_days_to_death
FROM mortality_stats;