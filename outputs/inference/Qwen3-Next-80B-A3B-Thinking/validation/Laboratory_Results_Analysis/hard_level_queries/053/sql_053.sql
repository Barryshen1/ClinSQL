WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON d_icd.icd_code = d_diag.icd_code AND d_icd.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (d_diag.long_title LIKE '%gastrointestinal hemorrhage%' OR d_diag.long_title LIKE '%lower GI bleeding%')
),
lab_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'CREATININE',
    'POTASSIUM',
    'PLATELET COUNT',
    'HEMOGLOBIN',
    'POTASSIUM WHOLE BLOOD',
    'WHITE BLOOD CELL COUNT'
  )
),
lab_events AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN lab_items d
    ON l.itemid = d.itemid
  WHERE l.valuenum IS NOT NULL
),
lab_abnormal_per_patient AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    l.itemid,
    MAX(CASE 
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 
      ELSE 0 
    END) AS has_abnormal
  FROM cohort c
  JOIN lab_events l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR
  GROUP BY c.subject_id, c.hadm_id, l.itemid
),
lab_score AS (
  SELECT 
    subject_id,
    hadm_id,
    SUM(has_abnormal) AS lab_score
  FROM lab_abnormal_per_patient
  GROUP BY subject_id, hadm_id
),
percentile AS (
  SELECT 
    PERCENTILE_CONT(lab_score, 0.9) AS p90
  FROM lab_score
),
top_tier AS (
  SELECT 
    ls.subject_id,
    ls.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM lab_score ls
  JOIN cohort c
    ON ls.subject_id = c.subject_id
    AND ls.hadm_id = c.hadm_id
  WHERE ls.lab_score >= (SELECT p90 FROM percentile)
),
mortality_los AS (
  SELECT 
    'mortality' AS metric,
    AVG(CAST(t.hospital_expire_flag AS FLOAT64)) AS top_tier,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS `all`
  FROM top_tier t
  CROSS JOIN cohort c
  UNION ALL
  SELECT 
    'avg_los' AS metric,
    AVG(TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY)) AS top_tier,
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS `all`
  FROM top_tier t
  CROSS JOIN cohort c
),
lab_rates AS (
  SELECT 
    d.label AS metric,
    AVG(CASE WHEN t.subject_id IS NOT NULL THEN lab_abnormal_per_patient.has_abnormal ELSE NULL END) AS top_tier,
    AVG(lab_abnormal_per_patient.has_abnormal) AS `all`
  FROM lab_abnormal_per_patient
  JOIN lab_items d
    ON lab_abnormal_per_patient.itemid = d.itemid
  LEFT JOIN top_tier t
    ON lab_abnormal_per_patient.subject_id = t.subject_id
    AND lab_abnormal_per_patient.hadm_id = t.hadm_id
  GROUP BY d.label
)
SELECT * FROM mortality_los
UNION ALL
SELECT * FROM lab_rates;