WITH dvt_cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND (LOWER(d_icd.long_title) LIKE '%deep vein thrombosis%'
         OR LOWER(d_icd.long_title) LIKE '%dvt%'
         OR d.icd_code LIKE 'I82%')
),

lab_abnormal_72h AS (
  SELECT 
    dc.subject_id,
    dc.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM dvt_cohort dc
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON dc.hadm_id = le.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE le.charttime >= dc.admittime
    AND le.charttime <= dc.admittime + INTERVAL 72 HOUR
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.flag = 'abnormal' 
         OR le.valuenum < le.ref_range_lower 
         OR le.valuenum > le.ref_range_upper)
  GROUP BY dc.subject_id, dc.hadm_id
),

percentile_95 AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.95) AS p95_score
  FROM lab_abnormal_72h
),

top_5_percent AS (
  SELECT 
    la.subject_id,
    la.hadm_id,
    la.lab_instability_score,
    dc.hospital_expire_flag,
    DATETIME_DIFF(dc.dischtime, dc.admittime, HOUR) / 24.0 AS hospital_los,
    CASE WHEN la.lab_instability_score >= p95.p95_score THEN 1 ELSE 0 END AS is_top_5_percent
  FROM lab_abnormal_72h la
  JOIN dvt_cohort dc ON la.subject_id = dc.subject_id AND la.hadm_id = dc.hadm_id
  CROSS JOIN percentile_95 p95
),

top_5_metrics AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(hospital_los) AS mean_los,
    AVG(CASE WHEN lab_instability_score >= (SELECT p95_score FROM percentile_95) THEN 1.0 ELSE 0.0 END) AS prop_with_abnormal_lab_top5
  FROM top_5_percent
  WHERE is_top_5_percent = 1
),

all_inpatients_baseline AS (
  SELECT 
    AVG(CASE WHEN la.lab_instability_score >= (SELECT p95_score FROM percentile_95) THEN 1.0 ELSE 0.0 END) AS prop_with_abnormal_lab_all
  FROM (
    SELECT 
      a.hadm_id,
      COUNT(*) AS lab_instability_score
    FROM physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON a.hadm_id = le.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
    WHERE le.charttime >= a.admittime
      AND le.charttime <= a.admittime + INTERVAL 72 HOUR
      AND le.valuenum IS NOT NULL
      AND le.ref_range_lower IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
      AND (le.flag = 'abnormal' 
           OR le.valuenum < le.ref_range_lower 
           OR le.valuenum > le.ref_range_upper)
    GROUP BY a.hadm_id
  ) AS la
)

SELECT 
  t.mortality_rate,
  t.mean_los,
  t.prop_with_abnormal_lab_top5,
  b.prop_with_abnormal_lab_all
FROM top_5_metrics t
CROSS JOIN all_inpatients_baseline b;