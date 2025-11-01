WITH
-- Define age range (38-48)
age_range AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
),

-- Patients with both T2D and HF
t2d_hf_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN age_range ar ON a.subject_id = ar.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.subject_id = a.subject_id
      AND di.hadm_id = a.hadm_id
      AND (d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E11.%') -- T2D
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.subject_id = a.subject_id
      AND di.hadm_id = a.hadm_id
      AND (d.icd_code LIKE 'I50%' OR d.icd_code LIKE 'I50.%') -- HF
  )
),

-- Insulin medications
insulin_meds AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
),

-- Oral diabetes medications
oral_meds AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'metformin', 'glipizide', 'glyburide', 'glimepiride',
    'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin'
  )
),

-- First 72h medications
first_72h_meds AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    MAX(CASE WHEN LOWER(p.drug) IN (SELECT drug FROM insulin_meds) THEN 1 ELSE 0 END) AS insulin_first_72h,
    MAX(CASE WHEN LOWER(p.drug) IN (SELECT drug FROM oral_meds) THEN 1 ELSE 0 END) AS oral_first_72h
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN t2d_hf_patients t ON p.subject_id = t.subject_id AND p.hadm_id = t.hadm_id
  WHERE p.starttime BETWEEN t.admittime AND TIMESTAMP_ADD(t.admittime, INTERVAL 72 HOUR)
  GROUP BY p.subject_id, p.hadm_id
),

-- Final 72h medications
final_72h_meds AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    MAX(CASE WHEN LOWER(p.drug) IN (SELECT drug FROM insulin_meds) THEN 1 ELSE 0 END) AS insulin_final_72h,
    MAX(CASE WHEN LOWER(p.drug) IN (SELECT drug FROM oral_meds) THEN 1 ELSE 0 END) AS oral_final_72h
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN t2d_hf_patients t ON p.subject_id = t.subject_id AND p.hadm_id = t.hadm_id
  WHERE p.starttime BETWEEN TIMESTAMP_SUB(t.dischtime, INTERVAL 72 HOUR) AND t.dischtime
  GROUP BY p.subject_id, p.hadm_id
),

-- Combined results
combined_results AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.insulin_first_72h,
    f.oral_first_72h,
    fi.insulin_final_72h,
    fi.oral_final_72h
  FROM first_72h_meds f
  JOIN final_72h_meds fi ON f.subject_id = fi.subject_id AND f.hadm_id = fi.hadm_id
)

-- Final aggregation
SELECT
  COUNT(*) AS total_patients,
  SUM(insulin_first_72h) AS insulin_first_72h_count,
  SUM(oral_first_72h) AS oral_first_72h_count,
  SUM(insulin_final_72h) AS insulin_final_72h_count,
  SUM(oral_final_72h) AS oral_final_72h_count,
  ROUND(SUM(insulin_first_72h) * 100.0 / COUNT(*), 2) AS insulin_first_72h_pct,
  ROUND(SUM(oral_first_72h) * 100.0 / COUNT(*), 2) AS oral_first_72h_pct,
  ROUND(SUM(insulin_final_72h) * 100.0 / COUNT(*), 2) AS insulin_final_72h_pct,
  ROUND(SUM(oral_final_72h) * 100.0 / COUNT(*), 2) AS oral_final_72h_pct
FROM combined_results;