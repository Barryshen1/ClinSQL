WITH 
-- Identify ischemic stroke admissions from ED for male Medicare patients aged 76-86
index_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Department'
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 'ICD-9' AND icd_code LIKE '433%')
        OR (icd_version = 'ICD-10' AND icd_code LIKE 'I63%')
    )
),

-- Flag readmitted patients within 30 days
readmitted_patients AS (
  SELECT 
    a1.hadm_id AS index_hadm_id,
    a2.hadm_id AS readm_hadm_id,
    CASE 
      WHEN 
        TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a2 
      ON a1.subject_id = a2.subject_id AND a1.dischtime < a2.admittime
)

-- Calculate desired metrics
SELECT 
  SUM(readmitted) AS readmitted_count,
  COUNT(DISTINCT ia.hadm_id) - SUM(readmitted) AS non_readmitted_count,
  APPROX_QUANTILES(
    TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY), 
    2, 
    STRUCT(0.5 AS percentile)
  )[OFFSET(1)] AS median_LOS,
  APPROX_QUANTILES(
    CASE 
      WHEN rp.readmitted = 1 THEN TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY) 
    END, 
    2, 
    STRUCT(0.5 AS percentile)
  )[OFFSET(1)] AS median_LOS_readmitted,
  APPROX_QUANTILES(
    CASE 
      WHEN rp.readmitted = 0 THEN TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY) 
    END, 
    2, 
    STRUCT(0.5 AS percentile)
  )[OFFSET(1)] AS median_LOS_non_readmitted,
  SUM(CASE WHEN TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY) > 5 THEN 1 ELSE 0 END) / COUNT(*) AS percent_stays_over_5_days
FROM 
  index_admissions ia
  LEFT JOIN readmitted_patients rp ON ia.hadm_id = rp.index_hadm_id;