WITH cohort AS (
  -- Base cohort: males 53-63 with both diabetes and heart failure diagnoses
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    AND a.hospital_expire_flag = 0  -- Alive discharges only
    AND EXISTS (
      -- Diabetes: any diagnosis with ICD-10 E08-E13
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND d2.icd_version = '10'
        AND d2.icd_code LIKE 'E[0-9][0-9]%'
        AND CAST(SUBSTR(d2.icd_code, 2, 2) AS INT64) BETWEEN 8 AND 13
    )
    AND EXISTS (
      -- Heart failure: any diagnosis with relevant ICD-10 codes
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
      WHERE d3.hadm_id = a.hadm_id
        AND d3.icd_version = '10'
        AND (d3.icd_code LIKE 'I50%' 
             OR d3.icd_code IN ('I11.0', 'I13.0', 'I13.2', 'I42.0'))
    )
),

glp1_items AS (
  -- Injectable GLP-1 RA itemids from d_items
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE ANY(
    '%semaglutide%', '%liraglutide%', '%dulaglutide%', '%exenatide%',
    '%albiglutide%', '%lixisenatide%', '%teduglutide%'  -- Common injectables
  )
),

glp1_events AS (
  -- GLP-1 RA administrations (focus on ICU inputs for injectables)
  SELECT DISTINCT ie.hadm_id, ie.starttime
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN cohort c ON ie.hadm_id = c.hadm_id
  INNER JOIN glp1_items g ON ie.itemid = g.itemid
  WHERE ie.amount > 0
    AND ie.ordercategoryname IN ('Continuous Med', 'Patient Med')
    AND ie.starttime >= c.admittime
    AND ie.starttime < c.dischtime
),

timing_flags AS (
  SELECT 
    c.hadm_id,
    -- First 24h from admission
    MAX(CASE WHEN ge.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) 
             THEN 1 ELSE 0 END) AS has_init_24h,
    -- Final 12h pre-discharge
    MAX(CASE WHEN ge.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) 
             AND ge.starttime < c.dischtime THEN 1 ELSE 0 END) AS has_pre_disch_12h
  FROM cohort c
  LEFT JOIN glp1_events ge ON c.hadm_id = ge.hadm_id
  GROUP BY c.hadm_id, c.admittime, c.dischtime
)

-- Final aggregations: percentages
SELECT 
  COUNT(DISTINCT c.hadm_id) AS total_cohort_size,
  SUM(tf.has_init_24h) AS num_with_24h_initiation,
  ROUND(SUM(tf.has_init_24h) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS pct_24h_initiation,
  SUM(tf.has_pre_disch_12h) AS num_with_12h_predischarge,
  ROUND(SUM(tf.has_pre_disch_12h) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS pct_12h_predischarge
FROM cohort c
INNER JOIN timing_flags tf ON c.hadm_id = tf.hadm_id;