WITH cohort AS (
  -- Male age 63-73 inpatient admissions with both T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
dx_flags AS (
  -- Identify which admissions have T2DM and which have HF
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  GROUP BY
    d.subject_id,
    d.hadm_id
),
cohort_dx AS (
  -- Restrict cohort to those with both conditions
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort AS c
    JOIN dx_flags AS dx
      ON c.subject_id = dx.subject_id
      AND c.hadm_id = dx.hadm_id
  WHERE
    dx.has_t2dm = 1
    AND dx.has_hf = 1
),
med_flags AS (
  -- For each admission, detect insulin and oral agent use in early vs late 24h
  SELECT
    cd.subject_id,
    cd.hadm_id,
    -- Early 24h window
    MAX(CASE 
        WHEN LOWER(p.drug) LIKE '%insulin%'
          AND p.stoptime >= cd.admittime
          AND p.starttime <= TIMESTAMP_ADD(cd.admittime, INTERVAL 24 HOUR)
        THEN 1 ELSE 0 END
    ) AS insulin_early,
    MAX(CASE 
        WHEN (
               LOWER(p.drug) LIKE '%metformin%'
            OR LOWER(p.drug) LIKE '%glipizide%'
            OR LOWER(p.drug) LIKE '%glyburide%'
            OR LOWER(p.drug) LIKE '%glimepiride%'
            OR LOWER(p.drug) LIKE '%sitagliptin%'
             )
          AND p.stoptime >= cd.admittime
          AND p.starttime <= TIMESTAMP_ADD(cd.admittime, INTERVAL 24 HOUR)
        THEN 1 ELSE 0 END
    ) AS oral_early,
    -- Late 24h window
    MAX(CASE 
        WHEN LOWER(p.drug) LIKE '%insulin%'
          AND p.stoptime >= TIMESTAMP_SUB(cd.dischtime, INTERVAL 24 HOUR)
          AND p.starttime <= cd.dischtime
        THEN 1 ELSE 0 END
    ) AS insulin_late,
    MAX(CASE 
        WHEN (
               LOWER(p.drug) LIKE '%metformin%'
            OR LOWER(p.drug) LIKE '%glipizide%'
            OR LOWER(p.drug) LIKE '%glyburide%'
            OR LOWER(p.drug) LIKE '%glimepiride%'
            OR LOWER(p.drug) LIKE '%sitagliptin%'
             )
          AND p.stoptime >= TIMESTAMP_SUB(cd.dischtime, INTERVAL 24 HOUR)
          AND p.starttime <= cd.dischtime
        THEN 1 ELSE 0 END
    ) AS oral_late
  FROM
    cohort_dx AS cd
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
      ON cd.subject_id = p.subject_id
      AND cd.hadm_id = p.hadm_id
  GROUP BY
    cd.subject_id,
    cd.hadm_id
),
aggregate_stats AS (
  SELECT
    COUNT(*) AS total_admissions,
    100.0 * SUM(insulin_early) / COUNT(*) AS insulin_early_pct,
    100.0 * SUM(insulin_late)  / COUNT(*) AS insulin_late_pct,
    100.0 * SUM(oral_early)    / COUNT(*) AS oral_early_pct,
    100.0 * SUM(oral_late)     / COUNT(*) AS oral_late_pct
  FROM
    med_flags
)
-- Final output: prevalence and net change
SELECT
  'Insulin' AS medication_class,
  ROUND(insulin_early_pct, 1) AS early_24h_pct,
  ROUND(insulin_late_pct, 1)  AS late_24h_pct,
  ROUND(insulin_late_pct - insulin_early_pct, 1) AS net_change_pp
FROM
  aggregate_stats
UNION ALL
SELECT
  'Oral agents' AS medication_class,
  ROUND(oral_early_pct, 1) AS early_24h_pct,
  ROUND(oral_late_pct, 1)  AS late_24h_pct,
  ROUND(oral_late_pct - oral_early_pct, 1) AS net_change_pp
FROM
  aggregate_stats;