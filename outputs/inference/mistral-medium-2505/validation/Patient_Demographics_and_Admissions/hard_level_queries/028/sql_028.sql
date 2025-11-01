WITH
-- Define cellulitis ICD codes (ICD-9 and ICD-10)
cellulitis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%cellulitis%'
),

-- Get female patients aged 55-65
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 55 AND 65
),

-- Get their admissions with Medicare insurance and ED admission
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMISSION'
),

-- Get first admission with principal diagnosis of cellulitis
index_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.los_days,
    pa.hospital_expire_flag
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pa.hadm_id = di.hadm_id
  JOIN cellulitis_codes cc ON di.icd_code = cc.icd_code
  WHERE pa.admission_seq = 1  -- First admission for each patient
    AND di.seq_num = 1  -- Principal diagnosis
),

-- Identify 30-day readmissions
readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.los_days AS index_los,
    ia.hospital_expire_flag,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
        WHERE ra.subject_id = ia.subject_id
          AND ra.hadm_id != ia.hadm_id
          AND ra.admittime BETWEEN ia.dischtime AND TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN TRUE
      ELSE FALSE
    END AS is_readmitted
  FROM index_admissions ia
)

-- Calculate final metrics
SELECT
  -- 30-day readmission rate
  ROUND(100 * SUM(CASE WHEN is_readmitted THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_rate_pct,

  -- Median LOS for readmitted vs non-readmitted
  ROUND(APPROX_QUANTILES(CASE WHEN is_readmitted THEN index_los ELSE NULL END, 100)[OFFSET(50)], 2) AS median_los_readmitted,
  ROUND(APPROX_QUANTILES(CASE WHEN NOT is_readmitted THEN index_los ELSE NULL END, 100)[OFFSET(50)], 2) AS median_los_non_readmitted,

  -- Percent of index stays >7 days
  ROUND(100 * SUM(CASE WHEN index_los > 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_index_stays_gt_7_days

FROM readmissions;