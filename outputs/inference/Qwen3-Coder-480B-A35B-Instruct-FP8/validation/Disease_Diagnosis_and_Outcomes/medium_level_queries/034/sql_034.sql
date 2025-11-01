WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
  ON
    d.icd_code = did.icd_code
    AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND LOWER(did.long_title) LIKE '%heart failure%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

grouped AS (
  SELECT
    *,
    CASE
      WHEN los_days < 8 THEN 'LOS < 8 days'
      ELSE 'LOS >= 8 days'
    END AS los_group
  FROM
    cohort
),

mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS n_admissions,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    APPROX_QUANTILES(
      CASE
        WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, HOUR)
        ELSE NULL
      END,
      2
    )[OFFSET(1)] AS median_time_to_death_hours
  FROM
    grouped
  GROUP BY
    los_group
)

SELECT
  los_group,
  n_admissions,
  ROUND(mortality_percent, 2) AS mortality_percent,
  median_time_to_death_hours
FROM
  mortality_stats
ORDER BY
  los_group;