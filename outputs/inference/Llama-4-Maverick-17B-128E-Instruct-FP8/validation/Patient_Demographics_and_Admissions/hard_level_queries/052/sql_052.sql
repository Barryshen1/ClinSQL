WITH 
-- Step 1: Filter patients based on age, gender, and insurance
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
),
-- Step 2: Identify admissions via ED with Medicare
ed_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.admission_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  WHERE a.insurance = 'Medicare' AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),
-- Step 3: Identify acute pancreatitis cases
acute_pancreatitis_admissions AS (
  SELECT ed.hadm_id
  FROM ed_admissions ed
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ed.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE di.seq_num = 1 AND LOWER(dicd.long_title) LIKE '%acute pancreatitis%'
),
-- Step 4: Calculate index LOS and readmission status
index_admissions AS (
  SELECT apa.hadm_id, ed.admittime, ed.dischtime, 
         DATETIME_DIFF(ed.dischtime, ed.admittime, HOUR) / 24 AS los,
         EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
           WHERE a2.subject_id = ed.subject_id AND a2.admittime > ed.dischtime AND DATETIME_DIFF(a2.admittime, ed.dischtime, DAY) <= 30
         ) AS readmitted
  FROM acute_pancreatitis_admissions apa
  JOIN ed_admissions ed ON apa.hadm_id = ed.hadm_id
)

-- Final calculations
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE COUNT(CASE WHEN readmitted THEN 1 END) / COUNT(*) 
  END AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted THEN los END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT readmitted THEN los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE SUM(CASE WHEN los > 9 THEN 1 ELSE 0 END) / COUNT(*) * 100 
  END AS percent_stays_gt_9_days
FROM index_admissions;