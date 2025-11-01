WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%sepsis%'
    )
),
lab_crit AS (
  SELECT
    c.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR
        (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      )
    ) AS crit_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort c
    ON le.hadm_id = c.hadm_id
   AND le.charttime BETWEEN c.admittime
                        AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
per_admission AS (
  SELECT
    c.hadm_id,
    COALESCE(lc.crit_count, 0) AS crit_count,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag AS died
  FROM cohort c
  LEFT JOIN lab_crit lc
    ON c.hadm_id = lc.hadm_id
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(AVG(crit_count), 2) AS mean_crit_events,
  ROUND(AVG(los_days), 2)   AS mean_los_days,
  ROUND(AVG(died), 3)       AS mortality_rate,
  -- 25th percentile of critical‐event counts
  APPROX_QUANTILES(crit_count, 100)[OFFSET(25)] AS pct25_crit_events
FROM per_admission;