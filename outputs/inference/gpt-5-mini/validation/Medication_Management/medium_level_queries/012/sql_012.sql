WITH
-- Cohort: female patients aged 50-60 with admission >=72h and both T2D and heart failure diagnoses
adms AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    -- admission length at least 72 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- diagnoses for each admission; flag T2D and heart failure using code patterns and long_title text
hadm_dx AS (
  SELECT di.hadm_id,
    MAX(
      CASE
        WHEN (
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
          OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
          OR (LOWER(d.long_title) LIKE '%diabetes%' AND LOWER(d.long_title) LIKE '%type 2%')
          OR (LOWER(d.long_title) LIKE '%diabetes%' AND LOWER(d.long_title) LIKE '%type ii%')
        ) THEN 1 ELSE 0 END
    ) AS has_t2d,
    MAX(
      CASE
        WHEN (
          (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
          OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
          OR (LOWER(d.long_title) LIKE '%heart failure%')
        ) THEN 1 ELSE 0 END
    ) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id
),

-- Cohort admissions that satisfy both diagnoses
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM adms a
  JOIN hadm_dx hx ON a.hadm_id = hx.hadm_id
  WHERE hx.has_t2d = 1 AND hx.has_hf = 1
),

-- GLP-1 medication events from prescriptions and pharmacy (hosp)
glp_med_presc AS (
  SELECT subject_id, hadm_id, starttime, stoptime, LOWER(drug) AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IS NOT NULL
),
glp_med_pharm AS (
  SELECT subject_id, hadm_id, starttime, stoptime, LOWER(medication) AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE medication IS NOT NULL
),

glp_all AS (
  SELECT subject_id, hadm_id, starttime, stoptime, med_text
  FROM glp_med_presc
  UNION ALL
  SELECT subject_id, hadm_id, starttime, stoptime, med_text
  FROM glp_med_pharm
),

-- Filter medication records to those matching GLP-1 agents (generic and common brand names)
glp_events AS (
  SELECT *,
    CAST(
      CASE
        WHEN med_text LIKE '%liraglutide%' THEN 1
        WHEN med_text LIKE '%semaglutide%' THEN 1
        WHEN med_text LIKE '%exenatide%' THEN 1
        WHEN med_text LIKE '%dulaglutide%' THEN 1
        WHEN med_text LIKE '%albiglutide%' THEN 1
        WHEN med_text LIKE '%lixisenatide%' THEN 1
        WHEN med_text LIKE '%victoza%' THEN 1
        WHEN med_text LIKE '%ozempic%' THEN 1
        WHEN med_text LIKE '%bydureon%' THEN 1
        WHEN med_text LIKE '%byetta%' THEN 1
        WHEN med_text LIKE '%trulicity%' THEN 1
        WHEN med_text LIKE '%rybelsus%' THEN 1
        ELSE 0
      END
    AS INT64) AS is_glp
  FROM glp_all
),
glp_filtered AS (
  SELECT subject_id, hadm_id, starttime, stoptime
  FROM glp_events
  WHERE is_glp = 1
),

-- For each cohort admission, determine flags: initiated within first 12 hours, on at 72 hours
hadm_flags AS (
  SELECT c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    -- first 12-hour initiation: any GLP record with starttime between admittime and admittime + 12h
    MAX(CASE WHEN g.starttime IS NOT NULL
                  AND g.starttime >= c.admittime
                  AND g.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS init_within_12h,
    -- on at 72 hours: any GLP record that started on/before admittime+72h and not stopped before that time
    MAX(CASE WHEN g.starttime IS NOT NULL
                  AND g.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
                  AND (g.stoptime IS NULL OR g.stoptime >= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR))
             THEN 1 ELSE 0 END) AS on_at_72h
  FROM cohort c
  LEFT JOIN glp_filtered g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id, c.subject_id, c.admittime, c.dischtime
)

SELECT
  COUNT(1) AS cohort_admissions,
  SUM(init_within_12h) AS n_initiated_first_12h,
  ROUND(100.0 * SAFE_DIVIDE(SUM(init_within_12h), COUNT(1)), 1) AS pct_initiated_first_12h,
  SUM(on_at_72h) AS n_on_at_72h,
  ROUND(100.0 * SAFE_DIVIDE(SUM(on_at_72h), COUNT(1)), 1) AS pct_on_at_72h,
  -- net percentage-point change (final prevalence minus initial initiation)
  ROUND(
    (100.0 * SAFE_DIVIDE(SUM(on_at_72h), COUNT(1)))
    - (100.0 * SAFE_DIVIDE(SUM(init_within_12h), COUNT(1))),
    1
  ) AS net_percentage_point_change
FROM hadm_flags;