WITH hadm_diag_flags AS (
  -- Aggregate diagnosis flags per hospital admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    MAX(CASE WHEN LOWER(dg.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock,
    MAX(CASE WHEN LOWER(dg.long_title) LIKE '%sepsis%' THEN 1 ELSE 0 END) AS has_sepsis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dg
      ON d.icd_code = dg.icd_code AND d.icd_version = dg.icd_version
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
),
cohort_hadm AS (
  -- Filter to target age/gender and label cohort
  SELECT
    h.*,
    CASE
      WHEN has_septic_shock = 1 THEN 'septic_shock'
      WHEN has_sepsis = 1 THEN 'sepsis'
      ELSE NULL
    END AS cohort,
    -- LOS in integer days (admission -> discharge)
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days_int,
    -- LOS bin using the integer day difference
    CASE WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_bin,
    -- time-to-death in fractional days (only meaningful for in-hospital deaths with deathtime)
    SAFE_DIVIDE(TIMESTAMP_DIFF(deathtime, admittime, SECOND), 86400) AS time_to_death_days
  FROM hadm_diag_flags h
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 53 AND 63
    AND (has_septic_shock = 1 OR has_sepsis = 1)
)
SELECT
  cohort,
  -- Counts and mortality for LOS <=7
  SUM(CASE WHEN los_bin = '<=7' THEN 1 ELSE 0 END) AS n_le7,
  SUM(CASE WHEN los_bin = '<=7' THEN hospital_expire_flag ELSE 0 END) AS deaths_le7,
  100 * SAFE_DIVIDE(
    SUM(CASE WHEN los_bin = '<=7' THEN hospital_expire_flag ELSE 0 END),
    NULLIF(SUM(CASE WHEN los_bin = '<=7' THEN 1 ELSE 0 END), 0)
  ) AS mort_pct_le7,
  -- median time-to-death in days among in-hospital decedents with LOS <=7 (approximate)
  APPROX_QUANTILES(
    CASE WHEN los_bin = '<=7' AND hospital_expire_flag = 1 THEN time_to_death_days ELSE NULL END,
    100
  )[OFFSET(50)] AS median_ttd_days_le7,

  -- Counts and mortality for LOS >7
  SUM(CASE WHEN los_bin = '>7' THEN 1 ELSE 0 END) AS n_gt7,
  SUM(CASE WHEN los_bin = '>7' THEN hospital_expire_flag ELSE 0 END) AS deaths_gt7,
  100 * SAFE_DIVIDE(
    SUM(CASE WHEN los_bin = '>7' THEN hospital_expire_flag ELSE 0 END),
    NULLIF(SUM(CASE WHEN los_bin = '>7' THEN 1 ELSE 0 END), 0)
  ) AS mort_pct_gt7,
  -- median time-to-death in days among in-hospital decedents with LOS >7 (approximate)
  APPROX_QUANTILES(
    CASE WHEN los_bin = '>7' AND hospital_expire_flag = 1 THEN time_to_death_days ELSE NULL END,
    100
  )[OFFSET(50)] AS median_ttd_days_gt7,

  -- Absolute and relative mortality differences (comparing >7 vs <=7)
  -- Absolute difference in percentage points
  100 * SAFE_DIVIDE(
    SUM(CASE WHEN los_bin = '>7' THEN hospital_expire_flag ELSE 0 END),
    NULLIF(SUM(CASE WHEN los_bin = '>7' THEN 1 ELSE 0 END), 0)
  )
  -
  100 * SAFE_DIVIDE(
    SUM(CASE WHEN los_bin = '<=7' THEN hospital_expire_flag ELSE 0 END),
    NULLIF(SUM(CASE WHEN los_bin = '<=7' THEN 1 ELSE 0 END), 0)
  ) AS abs_diff_pct_points,

  -- Relative difference: ratio mort_pct_gt7 / mort_pct_le7
  SAFE_DIVIDE(
    100 * SAFE_DIVIDE(
      SUM(CASE WHEN los_bin = '>7' THEN hospital_expire_flag ELSE 0 END),
      NULLIF(SUM(CASE WHEN los_bin = '>7' THEN 1 ELSE 0 END), 0)
    ),
    100 * SAFE_DIVIDE(
      SUM(CASE WHEN los_bin = '<=7' THEN hospital_expire_flag ELSE 0 END),
      NULLIF(SUM(CASE WHEN los_bin = '<=7' THEN 1 ELSE 0 END), 0)
    )
  ) AS rel_diff_ratio,

  -- Relative percent change: (mort_gt7 - mort_le7) / mort_le7 * 100
  SAFE_DIVIDE(
    100 * SAFE_DIVIDE(
      SUM(CASE WHEN los_bin = '>7' THEN hospital_expire_flag ELSE 0 END),
      NULLIF(SUM(CASE WHEN los_bin = '>7' THEN 1 ELSE 0 END), 0)
    )
    -
    100 * SAFE_DIVIDE(
      SUM(CASE WHEN los_bin = '<=7' THEN hospital_expire_flag ELSE 0 END),
      NULLIF(SUM(CASE WHEN los_bin = '<=7' THEN 1 ELSE 0 END), 0)
    ),
    NULLIF(100 * SAFE_DIVIDE(
      SUM(CASE WHEN los_bin = '<=7' THEN hospital_expire_flag ELSE 0 END),
      NULLIF(SUM(CASE WHEN los_bin = '<=7' THEN 1 ELSE 0 END), 0)
    ), 0)
  ) * 100 AS rel_diff_percent_change

FROM cohort_hadm
GROUP BY cohort
ORDER BY cohort;