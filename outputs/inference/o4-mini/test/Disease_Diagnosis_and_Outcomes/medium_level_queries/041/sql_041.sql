WITH sepsis_admissions AS (
  -- 1. Base admissions of 50–60 y/o females with sepsis but NOT septic shock
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    -- include sepsis ICD codes (example list)
    AND d.icd_code IN (
      '99591','99592',  -- Sepsis codes ICD-9
      'A41.0','A41.9','R65.20'  -- Sepsis codes ICD-10
    )
    -- exclude any admission that also has a septic shock code
    AND a.hadm_id NOT IN (
      SELECT dd.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      WHERE dd.subject_id = a.subject_id
        AND dd.icd_code IN (
          '78552',   -- Septic shock ICD-9
          'R65.21'   -- Septic shock ICD-10
        )
    )
),
cohort AS (
  -- 2. Compute LOS and time-to-death
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    IF(hospital_expire_flag = 1,
       TIMESTAMP_DIFF(deathtime, admittime, DAY),
       NULL
    ) AS ttd_days
  FROM sepsis_admissions
),
stats AS (
  -- 3. Aggregate by LOS group
  SELECT
    IF(los_days <= 7, '≤7', '>7') AS los_group,
    COUNT(*)                  AS total_admissions,
    SUM(hospital_expire_flag) AS deaths,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
    -- median time-to-death among those who died
    APPROX_QUANTILES(ttd_days, 2)[OFFSET(1)] AS median_ttd_days
  FROM cohort
  GROUP BY los_group
),
diffs AS (
  -- 4. Compute absolute and relative differences
  SELECT
    'Difference' AS los_group,
    NULL        AS total_admissions,
    NULL        AS deaths,
    s_gt7.mortality_pct - s_le7.mortality_pct            AS mortality_pct,
    NULL                                                AS median_ttd_days,
    s_gt7.mortality_pct - s_le7.mortality_pct            AS abs_diff_pct,
    SAFE_DIVIDE(
      s_gt7.mortality_pct - s_le7.mortality_pct,
      s_le7.mortality_pct
    ) * 100                                              AS rel_diff_pct
  FROM
    stats s_le7
    JOIN stats s_gt7
      ON s_le7.los_group = '≤7'
     AND s_gt7.los_group = '>7'
)
-- 5. Final output: two LOS groups plus the difference row
SELECT
  los_group,
  total_admissions,
  deaths,
  ROUND(mortality_pct, 2)    AS mortality_pct,
  median_ttd_days
FROM stats

UNION ALL

SELECT
  los_group,
  total_admissions,
  deaths,
  ROUND(mortality_pct, 2)    AS mortality_pct,
  median_ttd_days
FROM diffs

ORDER BY
  CASE los_group
    WHEN '≤7' THEN 1
    WHEN '>7' THEN 2
    ELSE 3
  END;