WITH hadm_cohort AS (
  -- admissions for male patients age 86-96 with sepsis diagnosis and WITHOUT septic shock
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    -- require admittime/dischtime present
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- has at least one diagnosis with "sepsis" in the description
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code
        AND di.icd_version = d.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%sepsis%'
    )
    -- exclude any admission that has a "septic shock" diagnosis
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
        ON di2.icd_code = d2.icd_code
        AND di2.icd_version = d2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND LOWER(d2.long_title) LIKE '%septic shock%'
    )
),

hadm_with_flags AS (
  SELECT
    h.*,
    -- hospital length of stay in days (integer days)
    TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    -- day-1 ICU flag: any icustay overlapping first 24 hours of the admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` s
        WHERE s.subject_id = h.subject_id
          AND s.hadm_id = h.hadm_id
          -- overlap condition: icu.intime < admittime + 1 day AND icu.outtime > admittime
          AND s.intime < TIMESTAMP_ADD(h.admittime, INTERVAL 1 DAY)
          AND s.outtime > h.admittime
      ) THEN 'Yes' ELSE 'No'
    END AS icu_day1,
    -- bucket LOS into requested bins
    CASE
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) <= 3 THEN '≤3'
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) BETWEEN 4 AND 6 THEN '4–6'
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) BETWEEN 7 AND 10 THEN '7–10'
      WHEN TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) > 10 THEN '>10'
      ELSE 'Unknown'
    END AS los_bucket,
    -- days to death (only meaningful if hospital_expire_flag = 1 and deathtime present)
    CASE
      WHEN h.hospital_expire_flag = 1 AND h.deathtime IS NOT NULL
      THEN TIMESTAMP_DIFF(h.deathtime, h.admittime, DAY)
      ELSE NULL
    END AS days_to_death
  FROM hadm_cohort h
)

SELECT
  los_bucket,
  icu_day1,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 2) AS mortality_pct,
  -- approximate median days-to-death among decedents in the group (50th percentile)
  -- APPROX_QUANTILES returns an array; OFFSET(1) selects the median when num_quantiles=2
  (APPROX_QUANTILES(days_to_death, 2))[OFFSET(1)] AS median_days_to_death_approx
FROM hadm_with_flags
GROUP BY los_bucket, icu_day1
ORDER BY
  -- order buckets logically
  CASE los_bucket
    WHEN '≤3' THEN 1
    WHEN '4–6' THEN 2
    WHEN '7–10' THEN 3
    WHEN '>10' THEN 4
    ELSE 5
  END,
  icu_day1 DESC;