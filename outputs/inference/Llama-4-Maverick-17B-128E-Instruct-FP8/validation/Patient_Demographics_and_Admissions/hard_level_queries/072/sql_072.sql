WITH 
index_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    p.anchor_age + EXTRACT(YEAR FROM (a.admittime)) - p.anchor_year AS age_at_admit,
    a.admission_location,
    a.insurance,
    di.long_title AS principal_diagnosis
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND di.long_title LIKE '%Acute respiratory failure%'
    AND d.seq_num = 1  
    AND p.anchor_age + EXTRACT(YEAR FROM (a.admittime)) - p.anchor_year BETWEEN 77 AND 87
),
admission_outcomes AS (
  SELECT 
    ia.subject_id, 
    ia.hadm_id, 
    ia.admittime, 
    ia.dischtime, 
    DATETIME_DIFF(ia.dischtime, ia.admittime, HOUR) / 24 AS index_los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND DATETIME_DIFF(a2.admittime, ia.dischtime, DAY) <= 30
    ) AS readmitted_30d
  FROM 
    index_admissions ia
),
outcome_stats AS (
  SELECT 
    readmitted_30d,
    index_los,
    index_los > 8 AS long_stay
  FROM 
    admission_outcomes
)
SELECT 
  AVG(CAST(readmitted_30d AS INT64)) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted_30d THEN index_los END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT readmitted_30d THEN index_los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  AVG(CAST(long_stay AS INT64)) AS percent_long_stay
FROM 
  outcome_stats;