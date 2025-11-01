WITH 
-- Filter patients based on age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 76 AND 86
),

-- Identify index admissions for AMI
index_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.admission_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE a.admission_location LIKE '%TRANSFER FROM HOSPITAL%'
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_code LIKE '410%' AND icd_version = 9)
    OR (icd_code LIKE 'I21%' AND icd_version = 10)
    AND seq_num = 1  -- Principal diagnosis
  )
),

-- Calculate index LOS and readmission status
index_outcomes AS (
  SELECT 
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    DATETIME_DIFF(ia.dischtime, ia.admittime, DAY) AS index_los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
      AND a2.admittime > ia.dischtime
      AND DATETIME_DIFF(a2.admittime, ia.dischtime, DAY) BETWEEN 0 AND 30
    ) AS readmitted
  FROM index_admissions ia
)

-- Calculate required metrics
SELECT 
  -- 30-day readmission rate
  AVG(CAST(readmitted AS INT64)) AS readmission_rate,
  -- Median index LOS for readmitted vs not
  APPROX_QUANTILES(CASE WHEN readmitted THEN index_los END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT readmitted THEN index_los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- Percent index stays >4 days
  AVG(CASE WHEN index_los > 4 THEN 1 ELSE 0 END) AS percent_stays_gt_4_days
FROM index_outcomes;