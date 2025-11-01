WITH dx_flags AS (
  SELECT
    hadm_id,
    MAX(CASE
          WHEN icd_version = 10 AND STARTS_WITH(icd_code, 'E11') THEN 1
          WHEN icd_version = 9  AND STARTS_WITH(icd_code, '250') THEN 1
          ELSE 0 END) AS has_t2dm,
    MAX(CASE
          WHEN icd_version = 10 AND STARTS_WITH(icd_code, 'I50') THEN 1
          WHEN icd_version = 9  AND STARTS_WITH(icd_code, '428') THEN 1
          ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
  HAVING has_t2dm = 1 AND has_hf = 1
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN dx_flags d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.dischtime IS NOT NULL
),

-- All candidate GLP-1 events from three inpatient medication tables (prescriptions, pharmacy, emar)
glp_events AS (
  -- prescriptions
  SELECT
    subject_id,
    hadm_id,
    starttime AS evt_time,
    LOWER(drug) AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    starttime IS NOT NULL
    AND (
      LOWER(drug) LIKE '%liraglutide%' OR
      LOWER(drug) LIKE '%semaglutide%' OR
      LOWER(drug) LIKE '%dulaglutide%' OR
      LOWER(drug) LIKE '%exenatide%' OR
      LOWER(drug) LIKE '%lixisenatide%' OR
      LOWER(drug) LIKE '%albiglutide%' OR
      LOWER(drug) LIKE '%efpeglenatide%' OR
      LOWER(drug) LIKE '%victoza%' OR
      LOWER(drug) LIKE '%ozempic%' OR
      LOWER(drug) LIKE '%trulicity%' OR
      LOWER(drug) LIKE '%byetta%'
    )

  UNION ALL

  -- pharmacy (inpatient dispensation)
  SELECT
    subject_id,
    hadm_id,
    starttime AS evt_time,
    LOWER(medication) AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    starttime IS NOT NULL
    AND (
      LOWER(medication) LIKE '%liraglutide%' OR
      LOWER(medication) LIKE '%semaglutide%' OR
      LOWER(medication) LIKE '%dulaglutide%' OR
      LOWER(medication) LIKE '%exenatide%' OR
      LOWER(medication) LIKE '%lixisenatide%' OR
      LOWER(medication) LIKE '%albiglutide%' OR
      LOWER(medication) LIKE '%efpeglenatide%' OR
      LOWER(medication) LIKE '%victoza%' OR
      LOWER(medication) LIKE '%ozempic%' OR
      LOWER(medication) LIKE '%trulicity%' OR
      LOWER(medication) LIKE '%byetta%'
    )

  UNION ALL

  -- emar (administration records)
  SELECT
    subject_id,
    hadm_id,
    charttime AS evt_time,
    LOWER(medication) AS med_text
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE
    charttime IS NOT NULL
    AND (
      LOWER(medication) LIKE '%liraglutide%' OR
      LOWER(medication) LIKE '%semaglutide%' OR
      LOWER(medication) LIKE '%dulaglutide%' OR
      LOWER(medication) LIKE '%exenatide%' OR
      LOWER(medication) LIKE '%lixisenatide%' OR
      LOWER(medication) LIKE '%albiglutide%' OR
      LOWER(medication) LIKE '%efpeglenatide%' OR
      LOWER(medication) LIKE '%victoza%' OR
      LOWER(medication) LIKE '%ozempic%' OR
      LOWER(medication) LIKE '%trulicity%' OR
      LOWER(medication) LIKE '%byetta%'
    )
),

-- Aggregate GLP events per admission and join to cohort to compute windows/flags
glp_by_adm AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    MIN(e.evt_time) AS first_evt,
    MAX(e.evt_time) AS last_evt,
    -- any GLP event before admission (0/1, coalesced to 0 when no events)
    COALESCE(MAX(CASE WHEN e.evt_time < c.admittime THEN 1 ELSE 0 END), 0) AS any_pre_admission,
    -- any GLP event in last 48 hours before discharge (0/1)
    COALESCE(MAX(CASE WHEN e.evt_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END), 0) AS any_in_last48
  FROM
    cohort c
    LEFT JOIN glp_events e
      ON c.hadm_id = e.hadm_id
  GROUP BY
    c.hadm_id, c.subject_id, c.admittime, c.dischtime
)

-- Final aggregated metrics
SELECT
  COUNT(*) AS cohort_admissions,
  SUM(CASE
        WHEN first_evt IS NOT NULL
         AND any_pre_admission = 0
         AND first_evt BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
        THEN 1 ELSE 0 END) AS started_within_72h_count,
  SAFE_DIVIDE(
    SUM(CASE
          WHEN first_evt IS NOT NULL
           AND any_pre_admission = 0
           AND first_evt BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0 END),
    COUNT(*)
  ) * 100.0 AS pct_started_within_72h,
  SUM(CASE WHEN any_in_last48 = 1 THEN 1 ELSE 0 END) AS on_in_last48h_count,
  SAFE_DIVIDE(SUM(CASE WHEN any_in_last48 = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100.0 AS pct_on_in_last48h,
  -- Net change defined here as (pct_on_in_last48h) - (pct_started_within_72h)
  (SAFE_DIVIDE(SUM(CASE WHEN any_in_last48 = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100.0)
  -
  (SAFE_DIVIDE(SUM(CASE
          WHEN first_evt IS NOT NULL
           AND any_pre_admission = 0
           AND first_evt BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0 END), COUNT(*)) * 100.0) AS net_change_pct
FROM
  glp_by_adm;