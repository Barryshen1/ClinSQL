WITH icd_stroke AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND di.icd_code LIKE 'I63%'
),
cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN icd_stroke s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admittime IS NOT NULL
),
lab_72h AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IN ('abnormal', 'critical')
    AND l.valuenum IS NOT NULL
  GROUP BY c.hadm_id
)
SELECT
  MIN(CASE WHEN c.is_stroke = 1 THEN COALESCE(l.abnormal_lab_count, 0) END) AS min_72h_lab_instability,
  AVG(CASE WHEN c.is_stroke = 1 THEN COALESCE(l.abnormal_lab_count, 0) END) AS avg_critical_labs_stroke,
  AVG(CASE WHEN c.is_stroke = 0 THEN COALESCE(l.abnormal_lab_count, 0) END) AS avg_critical_labs_general,
  AVG(CASE WHEN c.is_stroke = 1 THEN c.los_days END) AS avg_los_stroke,
  AVG(CASE WHEN c.is_stroke = 1 THEN c.hospital_expire_flag END) AS mortality_rate_stroke
FROM cohort c
LEFT JOIN lab_72h l ON c.hadm_id = l.hadm_id
GROUP BY ();  -- Ensures single row output;