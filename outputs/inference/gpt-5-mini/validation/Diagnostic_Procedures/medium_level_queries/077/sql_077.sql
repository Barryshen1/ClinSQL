WITH septic_admissions AS (
  -- Admissions of female patients age 57-67 with a diagnosis labeled "septic shock"
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_bin,
    CASE
      WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    -- require a septic shock diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%septic shock%'
    )
    -- restrict to admissions with LOS 1-7 days
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 7
),

us_events_per_adm AS (
  -- Count ultrasound / echo related HCPCS events per admission (billing events)
  SELECT
    h.hadm_id,
    COUNT(*) AS us_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE (
    -- check the long_description or short_description for ultrasound/echo keywords
    (d.long_description IS NOT NULL AND (
       LOWER(d.long_description) LIKE '%ultrasound%' OR
       LOWER(d.long_description) LIKE '%sonography%' OR
       LOWER(d.long_description) LIKE '%sonogram%' OR
       LOWER(d.long_description) LIKE '%echo%' OR
       LOWER(d.long_description) LIKE '%echocardi%' OR
       LOWER(d.long_description) LIKE '%echocardiogram%' OR
       LOWER(d.long_description) LIKE '%transthorac%' OR
       LOWER(d.long_description) LIKE '%transesophag%'
    ))
    OR
    (h.short_description IS NOT NULL AND (
       LOWER(h.short_description) LIKE '%ultrasound%' OR
       LOWER(h.short_description) LIKE '%sonography%' OR
       LOWER(h.short_description) LIKE '%sonogram%' OR
       LOWER(h.short_description) LIKE '%echo%' OR
       LOWER(h.short_description) LIKE '%echocardi%' OR
       LOWER(h.short_description) LIKE '%echocardiogram%' OR
       LOWER(h.short_description) LIKE '%transthorac%' OR
       LOWER(h.short_description) LIKE '%transesophag%'
    ))
  )
  GROUP BY h.hadm_id
),

admissions_with_us AS (
  -- Left join to include admissions with zero ultrasounds
  SELECT
    s.hadm_id,
    s.los_bin,
    s.icu_flag,
    COALESCE(u.us_count, 0) AS us_count
  FROM septic_admissions s
  LEFT JOIN us_events_per_adm u
    ON s.hadm_id = u.hadm_id
  WHERE s.los_bin IS NOT NULL  -- keep only 1-3 or 4-7 bins
)

SELECT
  los_bin,
  icu_flag,
  -- APPROX_QUANTILES(..., 4) returns an array like [min, p25, p50, p75, max]
  APPROX_QUANTILES(us_count, 4)[OFFSET(1)] AS p25_ultrasounds_per_admission,
  APPROX_QUANTILES(us_count, 4)[OFFSET(2)] AS p50_ultrasounds_per_admission,
  APPROX_QUANTILES(us_count, 4)[OFFSET(3)] AS p75_ultrasounds_per_admission,
  COUNT(*) AS n_admissions_in_group
FROM admissions_with_us
GROUP BY los_bin, icu_flag
ORDER BY los_bin, icu_flag;