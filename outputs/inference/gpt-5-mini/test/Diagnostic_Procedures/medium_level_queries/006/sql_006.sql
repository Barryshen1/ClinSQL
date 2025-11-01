WITH
-- Admissions for male patients aged 48-58 with non-null times
base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- keep LOS window 1-8 only (we will bucket 1-4 and 5-8)
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 8
),

-- Admissions with sepsis diagnosis (text match on diagnosis description)
admissions_with_sepsis AS (
  SELECT DISTINCT d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
),

-- Admissions with any shock diagnosis (to be excluded)
admissions_with_shock AS (
  SELECT DISTINCT d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%shock%'
),

-- ICU flag per admission
admission_icu_flag AS (
  SELECT
    hadm_id,
    TRUE AS had_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

-- Ultrasound events from hcpcsevents (HOSP)
us_from_hcpcs AS (
  SELECT
    h.hadm_id,
    COUNT(1) AS us_events
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON h.hcpcs_cd = d.code
  WHERE
    LOWER(d.long_description) LIKE '%ultrasound%'
  GROUP BY h.hadm_id
),

-- Ultrasound procedures from procedures_icd (HOSP)
us_from_proc_icd AS (
  SELECT
    p.hadm_id,
    COUNT(1) AS us_events
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY p.hadm_id
),

-- Ultrasound procedureevents in ICU (ICU module)
us_from_proc_events_icu AS (
  SELECT
    p.hadm_id,
    COUNT(1) AS us_events
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON p.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%ultrasound%'
  GROUP BY p.hadm_id
),

-- Union ultrasound counts per admission (sum across sources)
ultrasound_counts AS (
  SELECT
    hadm_id,
    SUM(us_events) AS ultrasound_count
  FROM (
    SELECT * FROM us_from_hcpcs
    UNION ALL
    SELECT * FROM us_from_proc_icd
    UNION ALL
    SELECT * FROM us_from_proc_events_icu
  )
  GROUP BY hadm_id
)

-- Final aggregation: filter base_admissions to sepsis (and not shock), attach ICU flag and ultrasound counts,
-- bucket LOS, then compute patient counts and mean ultrasounds per admission
SELECT
  CASE WHEN icu.had_icu IS TRUE THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  CASE
    WHEN ba.los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
    WHEN ba.los_days BETWEEN 5 AND 8 THEN 'LOS_5_8'
    ELSE 'OTHER'
  END AS los_bucket,
  COUNT(DISTINCT ba.subject_id) AS patient_count,
  COUNT(DISTINCT ba.hadm_id) AS admission_count,
  ROUND(AVG(COALESCE(u.ultrasound_count, 0)), 3) AS mean_ultrasounds_per_admission,
  SUM(COALESCE(u.ultrasound_count, 0)) AS total_ultrasounds
FROM
  base_admissions ba
  JOIN admissions_with_sepsis s
    ON ba.hadm_id = s.hadm_id
  LEFT JOIN admissions_with_shock sh
    ON ba.hadm_id = sh.hadm_id
  LEFT JOIN admission_icu_flag icu
    ON ba.hadm_id = icu.hadm_id
  LEFT JOIN ultrasound_counts u
    ON ba.hadm_id = u.hadm_id
WHERE
  sh.hadm_id IS NULL
GROUP BY
  CASE WHEN icu.had_icu IS TRUE THEN 'ICU' ELSE 'No ICU' END,
  CASE
    WHEN ba.los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
    WHEN ba.los_days BETWEEN 5 AND 8 THEN 'LOS_5_8'
    ELSE 'OTHER'
  END
ORDER BY
  icu_status, los_bucket;