WITH cohort AS (
  -- Base cohort: males 89-99 with lower GI bleed admission
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id 
    AND a.hadm_id = SAFE_CAST(d.hadm_id AS INT64)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.anchor_age BETWEEN 89 AND 99
    AND p.gender = 'M'
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    AND (
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'K92.%') OR
      (d.icd_version = 'ICD-9' AND d.icd_code = '569.3')
    )
),

lab_data AS (
  -- Labs in 72h window for cohort
  SELECT 
    c.hadm_id,
    l.itemid,
    l.valuenum,
    l.charttime,
    li.label
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = SAFE_CAST(l.hadm_id AS INT64)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND li.label IN (
      'Hemoglobin', 'Platelet count', 
      'Sodium', 'Potassium', 'Creatinine', 'BUN', 'Albumin', 'Total bilirubin',
      'INR', 'PTT'
    )
),

instability AS (
  -- Compute CV per lab, then mean CV per hadm_id
  SELECT 
    hadm_id,
    AVG(
      CASE 
        WHEN mean_val > 0 THEN STDDEV_SAMP(valuenum) / mean_val 
        ELSE 0 
      END
    ) AS instability_score
  FROM (
    SELECT 
      hadm_id,
      itemid,
      AVG(valuenum) AS mean_val,
      STDDEV_SAMP(valuenum) AS std_val
    FROM lab_data
    GROUP BY hadm_id, itemid
  )
  GROUP BY hadm_id
),

quintiles AS (
  -- Add quintiles and outcomes
  SELECT 
    i.hadm_id,
    i.instability_score,
    NTILE(5) OVER (ORDER BY i.instability_score) AS quintile,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM instability i
  INNER JOIN cohort c ON i.hadm_id = c.hadm_id
),

critical_cohort AS (
  -- Critical labs in 72h for cohort
  SELECT DISTINCT
    ld.hadm_id
  FROM lab_data ld
  WHERE (
    -- Hb <7
    (ld.label = 'Hemoglobin' AND ld.valuenum < 7) OR
    -- Platelets <50k
    (ld.label = 'Platelet count' AND ld.valuenum < 50000) OR
    -- Na <130 or >150
    (ld.label = 'Sodium' AND (ld.valuenum < 130 OR ld.valuenum > 150)) OR
    -- K <3 or >5.5
    (ld.label = 'Potassium' AND (ld.valuenum < 3 OR ld.valuenum > 5.5)) OR
    -- Creat >2
    (ld.label = 'Creatinine' AND ld.valuenum > 2) OR
    -- BUN >40
    (ld.label = 'BUN' AND ld.valuenum > 40) OR
    -- Albumin <2.5
    (ld.label = 'Albumin' AND ld.valuenum < 2.5) OR
    -- Bilirubin >3
    (ld.label = 'Total bilirubin' AND ld.valuenum > 3) OR
    -- INR >2
    (ld.label = 'INR' AND ld.valuenum > 2) OR
    -- PTT >50
    (ld.label = 'PTT' AND ld.valuenum > 50)
  )
),

general_cohort AS (
  -- All male inpatients 89-99 (no GI bleed filter)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 89 AND 99
    AND p.gender = 'M'
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),

general_lab_data AS (
  -- Same labs for general cohort
  SELECT 
    gc.hadm_id,
    l.itemid,
    l.valuenum,
    l.charttime,
    li.label
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON gc.subject_id = l.subject_id 
    AND gc.hadm_id = SAFE_CAST(l.hadm_id AS INT64)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.charttime >= gc.admittime
    AND l.charttime <= TIMESTAMP_ADD(gc.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND li.label IN (
      'Hemoglobin', 'Platelet count', 
      'Sodium', 'Potassium', 'Creatinine', 'BUN', 'Albumin', 'Total bilirubin',
      'INR', 'PTT'
    )
),

general_critical AS (
  -- Critical labs for general cohort
  SELECT DISTINCT
    gld.hadm_id
  FROM general_lab_data gld
  WHERE (
    (gld.label = 'Hemoglobin' AND gld.valuenum < 7) OR
    (gld.label = 'Platelet count' AND gld.valuenum < 50000) OR
    (gld.label = 'Sodium' AND (gld.valuenum < 130 OR gld.valuenum > 150)) OR
    (gld.label = 'Potassium' AND (gld.valuenum < 3 OR gld.valuenum > 5.5)) OR
    (gld.label = 'Creatinine' AND gld.valuenum > 2) OR
    (gld.label = 'BUN' AND gld.valuenum > 40) OR
    (gld.label = 'Albumin' AND gld.valuenum < 2.5) OR
    (gld.label = 'Total bilirubin' AND gld.valuenum > 3) OR
    (gld.label = 'INR' AND gld.valuenum > 2) OR
    (gld.label = 'PTT' AND gld.valuenum > 50)
  )
),

-- Aggregates for quintiles
quintile_summary AS (
  SELECT 
    quintile,
    AVG(los_days) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
    COUNT(DISTINCT CASE WHEN cc.hadm_id IS NOT NULL THEN q.hadm_id END) * 100.0 / COUNT(DISTINCT q.hadm_id) AS critical_rate_pct
  FROM quintiles q
  LEFT JOIN critical_cohort cc ON q.hadm_id = cc.hadm_id
  GROUP BY quintile
),

-- General rate
general_rate AS (
  SELECT 
    'General' AS quintile,
    NULL AS avg_los,
    NULL AS mortality_pct,
    COUNT(DISTINCT gc.hadm_id) * 100.0 / COUNT(DISTINCT g.hadm_id) AS critical_rate_pct
  FROM general_cohort g
  LEFT JOIN general_critical gc ON g.hadm_id = gc.hadm_id
)

-- Combine
SELECT * FROM quintile_summary
UNION ALL
SELECT * FROM general_rate
ORDER BY 
  CASE WHEN quintile = 'General' THEN 6 ELSE CAST(quintile AS INT64) END;