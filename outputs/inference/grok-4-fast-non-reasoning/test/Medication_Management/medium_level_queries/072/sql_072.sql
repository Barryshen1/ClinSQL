WITH cohort AS (
  -- Base cohort: males 79-89
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type != 'OBSERVATION'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24  -- Ensure meaningful final 24h
),

t2d AS (
  -- Type 2 diabetes (primary diagnosis)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND dd.icd_code LIKE 'E11.%'
),

hf AS (
  -- Heart failure (any diagnosis)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE dd.icd_code LIKE 'I50.%'
     OR dd.icd_code IN ('I11.0', 'I13.0', 'I13.2')
),

qualified_cohort AS (
  -- Intersect conditions
  SELECT c.*
  FROM cohort c
  INNER JOIN t2d t ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  INNER JOIN hf h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),

glp1_prescriptions AS (
  -- GLP-1 initiations
  SELECT DISTINCT pr.subject_id, pr.hadm_id, pr.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN qualified_cohort qc
    ON pr.subject_id = qc.subject_id AND pr.hadm_id = qc.hadm_id
  WHERE pr.drug LIKE '%semaglutide%'
     OR pr.drug LIKE '%liraglutide%'
     OR pr.drug LIKE '%exenatide%'
     OR pr.drug LIKE '%dulaglutide%'
     OR pr.drug LIKE '%albiglutide%'
     OR pr.drug LIKE '%lixisenatide%'
     AND pr.starttime IS NOT NULL
)

SELECT 
  COUNT(*) AS cohort_size,
  -- Early initiation (first 12h)
  COUNTIF(early_flag = 1) AS early_initiators,
  SAFE_DIVIDE(COUNTIF(early_flag = 1), COUNT(*)) * 100 AS percent_early,
  -- Late initiation (final 24h pre-discharge)
  COUNTIF(late_flag = 1) AS late_initiators,
  SAFE_DIVIDE(COUNTIF(late_flag = 1), COUNT(*)) * 100 AS percent_late,
  -- Net percentage-point change
  SAFE_DIVIDE(COUNTIF(late_flag = 1), COUNT(*)) * 100 - 
  SAFE_DIVIDE(COUNTIF(early_flag = 1), COUNT(*)) * 100 AS net_change_pct_points
FROM (
  SELECT 
    qc.hadm_id,
    qc.admittime,
    qc.dischtime,
    -- Flag early initiation
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM glp1_prescriptions g 
        WHERE g.subject_id = qc.subject_id 
          AND g.hadm_id = qc.hadm_id
          AND g.starttime >= qc.admittime 
          AND g.starttime < TIMESTAMP_ADD(qc.admittime, INTERVAL 12 HOUR)
      ) THEN 1 ELSE 0 
    END AS early_flag,
    -- Flag late initiation
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM glp1_prescriptions g 
        WHERE g.subject_id = qc.subject_id 
          AND g.hadm_id = qc.hadm_id
          AND g.starttime >= TIMESTAMP_SUB(qc.dischtime, INTERVAL 24 HOUR)
          AND g.starttime < qc.dischtime
      ) THEN 1 ELSE 0 
    END AS late_flag
  FROM qualified_cohort qc
);