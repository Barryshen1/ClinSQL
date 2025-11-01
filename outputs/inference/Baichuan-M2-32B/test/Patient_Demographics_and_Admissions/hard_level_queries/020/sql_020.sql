WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 76 AND 86
),
admissions_filtered AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    a.admission_type,
    a.insurance,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE a.admission_type = 'transfer from another hospital'
    AND a.insurance LIKE '%Medicare%'
    AND a.hospital_expire_flag = 0
),
principal_diagnoses AS (
  SELECT 
    subject_id,
    hadm_id,
    icd_code,
    icd_version,
    seq_num,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY seq_num) AS diag_rank
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND icd_code LIKE 'I21%')
),
index_admissions AS (
  SELECT 
    af.subject_id,
    af.hadm_id,
    af.admittime,
    af.dischtime,
    af.los,
    af.hospital_expire_flag,
    af.insurance,
    af.admission_type
  FROM admissions_filtered af
  INNER JOIN principal_diagnoses pd 
    ON af.subject_id = pd.subject_id 
    AND af.hadm_id = pd.hadm_id
    AND pd.diag_rank = 1  -- principal diagnosis
  QUALIFY ROW_NUMBER() OVER (PARTITION BY af.subject_id ORDER BY af.admittime) = 1
),
readmission_check AS (
  SELECT 
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM index_admissions ia
),
index_with_readmission AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los,
    hospital_expire_flag,
    insurance,
    admission_type,
    readmitted
  FROM readmission_check
),
-- Compute medians for LOS by readmission group using APPROX_QUANTILES
medians AS (
  SELECT 
    readmitted,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
  FROM index_with_readmission
  GROUP BY readmitted
),
pivoted_medians AS (
  SELECT
    MAX(IF(readmitted, median_los, NULL)) AS median_los_readmitted,
    MAX(IF(NOT readmitted, median_los, NULL)) AS median_los_not_readmitted
  FROM medians
),
-- Compute overall metrics
metrics AS (
  SELECT 
    COUNT(*) AS total_index_admissions,
    SUM(CAST(readmitted AS INT)) AS readmitted_count,
    SUM(CASE WHEN los > 4 THEN 1 ELSE 0 END) AS los_gt4_count,
    (SUM(CAST(readmitted AS INT)) * 100.0 / NULLIF(COUNT(*), 0)) AS readmission_rate,
    (SUM(CASE WHEN los > 4 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0)) AS percent_los_gt4
  FROM index_with_readmission
)
SELECT 
  m.readmission_rate,
  m.percent_los_gt4,
  pm.median_los_readmitted,
  pm.median_los_not_readmitted
FROM metrics m
CROSS JOIN pivoted_medians pm;