WITH acs_icd_codes AS (
  -- List of ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '411', 9 UNION ALL
  SELECT '413', 9 UNION ALL
  SELECT 'I20', 10 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I22', 10 UNION ALL
  SELECT 'I23', 10 UNION ALL
  SELECT 'I24', 10
),
ultrasound_icd_codes AS (
  -- List of ultrasound/echo ICD-9 procedure codes
  SELECT '88.72' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '88.73', 9 UNION ALL
  SELECT '88.74', 9 UNION ALL
  SELECT '88.76', 9 UNION ALL
  SELECT '88.77', 9 UNION ALL
  SELECT '88.79', 9
),
cohort AS (
  -- Step 1: Find admissions for male patients age 39–49 with ACS and LOS 1–7 days
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
acs_admissions AS (
  -- Step 2: Find ACS admissions and ACS type (primary/secondary)
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(d.seq_num) AS min_seq_num
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
    JOIN acs_icd_codes acs
      ON d.icd_code = acs.icd_code AND d.icd_version = acs.icd_version
  GROUP BY
    c.subject_id, c.hadm_id
),
acs_type AS (
  -- Step 3: Assign ACS type
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE WHEN a.min_seq_num = 1 THEN 'primary' ELSE 'secondary' END AS acs_type
  FROM
    acs_admissions a
),
icu_stay_counts AS (
  -- Step 4: Count ICU stays per admission
  SELECT
    icu.hadm_id,
    COUNT(DISTINCT icu.stay_id) AS icu_stay_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  GROUP BY
    icu.hadm_id
),
icu_strata AS (
  -- Step 5: Bin ICU stay counts
  SELECT
    icu.hadm_id,
    icu.icu_stay_count,
    CASE
      WHEN icu.icu_stay_count BETWEEN 1 AND 4 THEN '1-4'
      WHEN icu.icu_stay_count BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS icu_stay_bin
  FROM
    icu_stay_counts icu
  WHERE
    icu.icu_stay_count BETWEEN 1 AND 7
),
ultrasound_counts AS (
  -- Step 6: Count ultrasounds/echo per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT p.icd_code) AS ultrasound_count
  FROM
    acs_type c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON c.hadm_id = p.hadm_id
    LEFT JOIN ultrasound_icd_codes uicd
      ON p.icd_code = uicd.icd_code AND p.icd_version = uicd.icd_version
  WHERE
    uicd.icd_code IS NOT NULL
  GROUP BY
    c.subject_id, c.hadm_id
),
final AS (
  -- Step 7: Combine all strata
  SELECT
    u.subject_id,
    u.hadm_id,
    u.ultrasound_count,
    a.acs_type,
    i.icu_stay_bin
  FROM
    ultrasound_counts u
    JOIN acs_type a
      ON u.hadm_id = a.hadm_id
    JOIN icu_strata i
      ON u.hadm_id = i.hadm_id
  WHERE
    i.icu_stay_bin IS NOT NULL
)
-- Step 8: Calculate percentiles per stratum
SELECT
  icu_stay_bin,
  acs_type,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75,
  COUNT(*) AS n_admissions
FROM
  final
GROUP BY
  icu_stay_bin, acs_type
ORDER BY
  icu_stay_bin, acs_type;