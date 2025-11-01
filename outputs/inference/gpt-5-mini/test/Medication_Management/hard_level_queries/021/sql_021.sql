WITH diag_flags AS (
  SELECT
    di.hadm_id,
    MAX(IF(COALESCE(LOWER(d.long_title), '') LIKE '%neutropen%', 1, 0)) AS has_neutropenia,
    MAX(IF(
      COALESCE(LOWER(d.long_title), '') LIKE '%fever%'
      OR COALESCE(LOWER(d.long_title), '') LIKE '%pyrexia%',
      1, 0)) AS has_fever
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY
    di.hadm_id
),

med_counts AS (
  -- Count distinct medication names prescribed within first 48 hours of admission
  SELECT
    a.hadm_id,
    COUNT(DISTINCT TRIM(LOWER(p.drug))) AS med_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = a.hadm_id
      AND p.starttime IS NOT NULL
      AND p.starttime >= a.admittime
      AND p.starttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
      AND TRIM(COALESCE(p.drug, '')) != ''
  GROUP BY
    a.hadm_id
),

cohort_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    COALESCE(mc.med_count, 0) AS med_count,
    -- LOS in fractional days
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days,
    -- 30-day readmission indicator as 0/1
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = a.subject_id
          AND a2.hadm_id != a.hadm_id
          AND a2.admittime > a.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
      ), 1, 0) AS has_readmit30
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN diag_flags df
      ON a.hadm_id = df.hadm_id
    LEFT JOIN med_counts mc
      ON a.hadm_id = mc.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    -- require both neutropenia and fever diagnosis in this admission
    AND df.has_neutropenia = 1
    AND df.has_fever = 1
),

cohort_with_tertile AS (
  SELECT
    cb.*,
    NTILE(3) OVER (ORDER BY cb.med_count, cb.hadm_id) AS tertile
  FROM
    cohort_base cb
)

SELECT
  tertile,
  COUNT(*) AS n_admissions,
  -- median LOS (approximate)
  (APPROX_QUANTILES(los_days, 100)[OFFSET(50)]) AS median_los_days,
  -- mean LOS for context
  AVG(los_days) AS mean_los_days,
  -- in-hospital mortality percent
  100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_pct,
  -- 30-day readmission percent
  100.0 * AVG(CAST(has_readmit30 AS FLOAT64)) AS readmit_30day_pct,
  -- medication count summary per tertile
  MIN(med_count) AS med_count_min,
  CAST(APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS INT64) AS med_count_median,
  MAX(med_count) AS med_count_max
FROM
  cohort_with_tertile
GROUP BY
  tertile
ORDER BY
  tertile;