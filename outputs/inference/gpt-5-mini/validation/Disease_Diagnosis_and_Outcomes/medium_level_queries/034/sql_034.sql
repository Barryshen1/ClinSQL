WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- elapsed seconds between admit and discharge
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) AS los_seconds
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- admission has at least one diagnosis whose long_title mentions "heart failure"
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
)

SELECT
  CASE
    WHEN los_seconds < 8 * 86400 THEN '<8 days'
    ELSE '>=8 days'
  END AS los_group,
  COUNT(*) AS admissions_N,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths_N,
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_pct,
  -- median time-to-death in days among in-hospital non-survivors (NULL if no deaths in group)
  CASE
    WHEN SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) = 0 THEN NULL
    ELSE APPROX_QUANTILES(
           -- time-to-death in days (fractional)
           IF(hospital_expire_flag = 1 AND deathtime IS NOT NULL,
              TIMESTAMP_DIFF(deathtime, admittime, SECOND) / 86400.0,
              NULL),
           2
         )[OFFSET(1)]
  END AS median_time_to_death_days
FROM cohort
GROUP BY los_group
ORDER BY los_group;