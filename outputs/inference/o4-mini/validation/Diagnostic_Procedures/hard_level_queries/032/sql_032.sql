WITH first_icu AS (
  -- First ICU stay for each female patient aged 66-76
  SELECT
    p.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime AS icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ic.intime) = 1
),
sepsis_flags AS (
  -- Mark which admissions have sepsis diagnoses
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    TRUE AS has_sepsis
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
),
cohort AS (
  -- Combine first ICU stay with sepsis flag; default FALSE for controls
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.icu_outtime,
    IFNULL(s.has_sepsis, FALSE) AS sepsis
  FROM
    first_icu f
    LEFT JOIN sepsis_flags s
      ON f.subject_id = s.subject_id
     AND f.hadm_id = s.hadm_id
),
proc_counts AS (
  -- Count distinct ICD procedures in first 48h of ICU
  SELECT
    c.subject_id,
    c.hadm_id,
    c.sepsis,
    COUNT(DISTINCT p.icd_code) AS proc_count
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON c.subject_id = p.subject_id
     AND c.hadm_id = p.hadm_id
     AND p.chartdate BETWEEN DATE(c.intime)
                         AND DATE_ADD(DATE(c.intime), INTERVAL 2 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.sepsis
),
hosp_stats AS (
  -- Join to admissions for LOS and mortality
  SELECT
    c.subject_id,
    c.hadm_id,
    c.sepsis,
    pc.proc_count,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days
  FROM
    cohort c
    JOIN proc_counts pc
      ON c.subject_id = pc.subject_id
     AND c.hadm_id = pc.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.hadm_id = a.hadm_id
)
-- Final output
SELECT
  'Sepsis 90th percentile of distinct procedures in first 48h' AS metric,
  CAST(
    (SELECT
       APPROX_QUANTILES(proc_count, 100)[OFFSET(90)]
     FROM hosp_stats
     WHERE sepsis = TRUE)
  AS INT64) AS value,
  NULL AS avg_los,
  NULL AS mortality_rate
UNION ALL
SELECT
  'Sepsis cohort - avg LOS (days)',
  NULL,
  ROUND(AVG(hosp_los_days), 2),
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4)
FROM hosp_stats
WHERE sepsis = TRUE
UNION ALL
SELECT
  'Control cohort - avg LOS (days)',
  NULL,
  ROUND(AVG(hosp_los_days), 2),
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4)
FROM hosp_stats
WHERE sepsis = FALSE
ORDER BY metric;