WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
dx AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    CASE
      WHEN MAX(CASE WHEN d.long_title LIKE '%septic shock%' THEN 1 ELSE 0 END) = 1 THEN 'septic_shock'
      WHEN MAX(CASE WHEN d.long_title LIKE '%sepsis%'       THEN 1 ELSE 0 END) = 1 THEN 'sepsis'
      ELSE NULL
    END AS sepsis_category
  FROM
    base b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON b.subject_id = di.subject_id
      AND b.hadm_id    = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code    = d.icd_code
      AND di.icd_version = d.icd_version
  GROUP BY
    b.subject_id,
    b.hadm_id
  HAVING
    MAX(CASE WHEN d.long_title LIKE '%septic shock%' THEN 1 ELSE 0 END) = 1
    OR MAX(CASE WHEN d.long_title LIKE '%sepsis%'       THEN 1 ELSE 0 END) = 1
),
with_los AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.deathtime,
    b.hospital_expire_flag,
    dx.sepsis_category,
    DATE_DIFF(b.dischtime, b.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(b.dischtime, b.admittime, DAY) <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group,
    CASE
      WHEN b.hospital_expire_flag = 1 THEN
        TIMESTAMP_DIFF(b.deathtime, b.admittime, DAY)
      ELSE NULL
    END AS time_to_death
  FROM
    base b
    JOIN dx
      ON b.subject_id = dx.subject_id
      AND b.hadm_id    = dx.hadm_id
),
agg AS (
  SELECT
    sepsis_category,
    los_group,
    COUNT(*) AS N,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mort_rate,
    -- approximate median time-to-death among those who died
    APPROX_QUANTILES(time_to_death, 2)[OFFSET(1)] AS median_time_to_death
  FROM
    with_los
  GROUP BY
    sepsis_category,
    los_group
),
pivoted AS (
  SELECT
    a.sepsis_category,
    a.N                    AS N_le7,
    a.mort_rate            AS mort_rate_le7,
    a.median_time_to_death AS median_ttd_le7,
    b.N                    AS N_gt7,
    b.mort_rate            AS mort_rate_gt7,
    b.median_time_to_death AS median_ttd_gt7
  FROM
    agg a
    JOIN agg b
      ON a.sepsis_category = b.sepsis_category
     AND a.los_group       = '<=7'
     AND b.los_group       = '>7'
)
SELECT
  sepsis_category,
  N_le7,
  mort_rate_le7,
  median_ttd_le7,
  N_gt7,
  mort_rate_gt7,
  median_ttd_gt7,
  mort_rate_gt7 - mort_rate_le7            AS abs_mort_diff,
  SAFE_DIVIDE(mort_rate_gt7, mort_rate_le7) AS rel_mort_diff
FROM
  pivoted
ORDER BY
  sepsis_category;