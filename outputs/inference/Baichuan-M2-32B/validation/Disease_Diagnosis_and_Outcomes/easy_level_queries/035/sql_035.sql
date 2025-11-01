WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(
      a.admittime, 
      TIMESTAMP(DATE_SUB(CAST(CONCAT(CAST(p.anchor_year AS STRING), '-01-01') AS DATE), INTERVAL p.anchor_age YEAR)), 
      YEAR
    ) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND TIMESTAMP_DIFF(
      a.admittime, 
      TIMESTAMP(DATE_SUB(CAST(CONCAT(CAST(p.anchor_year AS STRING), '-01-01') AS DATE), INTERVAL p.anchor_age YEAR)), 
      YEAR
    ) = 70
    AND a.dischtime IS NOT NULL
),
primary_diagnoses AS (
  SELECT 
    d.hadm_id,
    di.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    d.seq_num = 1
    AND (
      LOWER(di.long_title) LIKE '%upper gastrointestinal hemorrhage%' OR 
      LOWER(di.long_title) LIKE '%upper gi bleed%'
    )
),
combined AS (
  SELECT 
    e.hadm_id,
    DATEDIFF(e.dischtime, e.admittime) AS los_days
  FROM eligible_admissions e
  INNER JOIN primary_diagnoses p 
    ON e.hadm_id = p.hadm_id
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los
FROM combined;