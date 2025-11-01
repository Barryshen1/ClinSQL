WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    -- require at least one HF diagnosis in this admission
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
hf_los_groups AS (
  SELECT
    CASE
      WHEN los_days < 8 THEN '<8 days'
      ELSE '>=8 days'
    END AS los_group,
    hospital_expire_flag,
    -- time_to_death in days for non-survivors
    SAFE_DIVIDE(
      TIMESTAMP_DIFF(deathtime, admittime, SECOND),
      86400
    ) AS time_to_death_days
  FROM hf_admissions
)
SELECT
  los_group AS los_category,
  COUNT(*) AS admission_count,
  100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*) AS mortality_rate_pct,
  -- median time-to-death among non-survivors
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 1 THEN time_to_death_days END,
    2
  )[OFFSET(1)] AS median_time_to_death_days
FROM hf_los_groups
GROUP BY los_group
ORDER BY los_group;