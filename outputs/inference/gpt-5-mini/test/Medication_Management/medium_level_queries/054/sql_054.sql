WITH diagnoses_flags AS (
  -- Per-admission flags for diabetes and heart failure based on diagnosis descriptions
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS diabetes_flag,
    MAX(
      CASE
        WHEN LOWER(ddi.long_title) LIKE '%heart failure%'
          OR LOWER(ddi.long_title) LIKE '%congestive%'
          OR LOWER(ddi.long_title) LIKE '%cardiac failure%'
        THEN 1 ELSE 0
      END
    ) AS hf_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON d.icd_code = ddi.icd_code
    AND d.icd_version = ddi.icd_version
  GROUP BY d.hadm_id
),
cohort AS (
  -- Male inpatients age 56-66 with both diabetes and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP(a.admittime) AS admittime_ts,
    TIMESTAMP(a.dischtime) AS dischtime_ts
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diagnoses_flags df
    ON a.hadm_id = df.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND a.dischtime IS NOT NULL
    AND df.diabetes_flag = 1
    AND df.hf_flag = 1
),
glp_meds AS (
  -- Candidate GLP-1 medication records from prescriptions, pharmacy, emar, and ICU inputevents
  SELECT
    hadm_id,
    subject_id,
    TIMESTAMP(starttime) AS med_ts,
    drug AS med_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(drug, '')),
      r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|taspoglutide)')
  UNION ALL
  SELECT
    hadm_id,
    subject_id,
    TIMESTAMP(starttime) AS med_ts,
    medication AS med_name
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(medication, '')),
      r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|taspoglutide)')
  UNION ALL
  SELECT
    hadm_id,
    subject_id,
    TIMESTAMP(charttime) AS med_ts,
    medication AS med_name
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE charttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(medication, '')),
      r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|taspoglutide)')
  UNION ALL
  -- ICU inputevents: try to capture textual descriptors from ordercategoryname, secondaryordercategoryname, or ordercomponenttypedescription
  SELECT
    hadm_id,
    subject_id,
    TIMESTAMP(starttime) AS med_ts,
    NULL AS med_name
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE starttime IS NOT NULL
    AND (
      REGEXP_CONTAINS(LOWER(COALESCE(ordercategoryname, '')),
        r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|taspoglutide)')
      OR REGEXP_CONTAINS(LOWER(COALESCE(secondaryordercategoryname, '')),
        r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|taspoglutide)')
      OR REGEXP_CONTAINS(LOWER(COALESCE(ordercomponenttypedescription, '')),
        r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|taspoglutide)')
    )
),
glp_meds_normalized AS (
  SELECT hadm_id, subject_id, med_ts, med_name
  FROM glp_meds
),
per_admission_flags AS (
  -- For each admission, determine whether any GLP-1 med was given in the first 48h and in the final 24h
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime_ts,
    c.dischtime_ts,
    -- COUNTIF(...) > 0 returns a BOOLEAN; used below in aggregation
    COUNTIF(
      m.med_ts IS NOT NULL
      AND m.med_ts BETWEEN c.admittime_ts AND TIMESTAMP_ADD(c.admittime_ts, INTERVAL 48 HOUR)
    ) > 0 AS first48_flag,
    COUNTIF(
      m.med_ts IS NOT NULL
      AND m.med_ts BETWEEN TIMESTAMP_SUB(c.dischtime_ts, INTERVAL 24 HOUR) AND c.dischtime_ts
    ) > 0 AS final24_flag
  FROM cohort c
  LEFT JOIN glp_meds_normalized m
    ON m.hadm_id = c.hadm_id
  GROUP BY
    c.hadm_id,
    c.subject_id,
    c.admittime_ts,
    c.dischtime_ts
)
SELECT
  COUNT(1) AS total_admissions,
  SUM(CASE WHEN first48_flag THEN 1 ELSE 0 END) AS n_first48,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN first48_flag THEN 1 ELSE 0 END), COUNT(1)), 2) AS pct_first48,
  SUM(CASE WHEN final24_flag THEN 1 ELSE 0 END) AS n_final24,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN final24_flag THEN 1 ELSE 0 END), COUNT(1)), 2) AS pct_final24,
  ROUND(
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN final24_flag THEN 1 ELSE 0 END), COUNT(1))
    - 100.0 * SAFE_DIVIDE(SUM(CASE WHEN first48_flag THEN 1 ELSE 0 END), COUNT(1))
  , 2) AS net_change_percentage_points
FROM per_admission_flags;