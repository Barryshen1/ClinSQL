WITH cohort AS (
  -- Get admissions for male patients aged 77-87 with diabetes and heart failure
  SELECT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 77 AND 87
    AND pat.gender = 'M'
    AND adm.hadm_id IN (
      -- Admissions with diabetes
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E1%' OR icd_code LIKE '250%'
    )
    AND adm.hadm_id IN (
      -- Admissions with heart failure
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%' OR icd_code LIKE '428%'
    )
),

los_filtered AS (
  -- Only include admissions with LOS >= 72 hours
  SELECT *
  FROM cohort
  WHERE TIMESTAMP_DIFF(dischtime, admittime, HOUR) >= 72
),

-- Get prescriptions for insulin and oral agents
meds AS (
  SELECT p.subject_id, p.hadm_id, p.starttime, p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      ELSE 'oral'
    END AS med_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN los_filtered lf
    ON p.hadm_id = lf.hadm_id
  WHERE (LOWER(p.drug) LIKE '%insulin%'
         OR LOWER(p.drug) LIKE '%glipizide%'
         OR LOWER(p.drug) LIKE '%glyburide%'
         OR LOWER(p.drug) LIKE '%metformin%'
         OR LOWER(p.drug) LIKE '%sitagliptin%'
         OR LOWER(p.drug) LIKE '%saxagliptin%'
         OR LOWER(p.drug) LIKE '%linagliptin%'
         OR LOWER(p.drug) LIKE '%canagliflozin%'
         OR LOWER(p.drug) LIKE '%dapagliflozin%'
         OR LOWER(p.drug) LIKE '%empagliflozin%'
         OR LOWER(p.drug) LIKE '%pioglitazone%'
         OR LOWER(p.drug) LIKE '%rosiglitazone%'
         OR LOWER(p.drug) LIKE '%nateglinide%'
         OR LOWER(p.drug) LIKE '%repaglinide%'
         OR LOWER(p.drug) LIKE '%acarbose%'
         OR LOWER(p.drug) LIKE '%miglitol%'
         OR LOWER(p.drug) LIKE '%tolbutamide%'
         OR LOWER(p.drug) LIKE '%glimepiride%'
         OR LOWER(p.drug) LIKE '%gliclazide%')
),

-- For each patient and med type, check initiation in first 48h and usage in final 72h
patient_meds AS (
  SELECT lf.subject_id, lf.hadm_id,
    MAX(CASE WHEN m.med_type = 'insulin' AND m.starttime <= TIMESTAMP_ADD(lf.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS insulin_initiated,
    MAX(CASE WHEN m.med_type = 'oral' AND m.starttime <= TIMESTAMP_ADD(lf.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS oral_initiated,
    MAX(CASE WHEN m.med_type = 'insulin' AND m.starttime >= TIMESTAMP_SUB(lf.dischtime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS insulin_in_final,
    MAX(CASE WHEN m.med_type = 'oral' AND m.starttime >= TIMESTAMP_SUB(lf.dischtime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS oral_in_final
  FROM los_filtered lf
  LEFT JOIN meds m
    ON lf.hadm_id = m.hadm_id
  GROUP BY lf.subject_id, lf.hadm_id
)

-- Aggregate to compute initiation rates and net change
SELECT
  COUNT(DISTINCT subject_id) AS total_patients,
  -- Insulin
  SUM(insulin_initiated) AS insulin_initiated_count,
  ROUND(SUM(insulin_initiated) * 100.0 / COUNT(DISTINCT subject_id), 2) AS insulin_initiation_rate,
  SUM(insulin_in_final) AS insulin_final_count,
  ROUND(SUM(insulin_in_final) * 100.0 / COUNT(DISTINCT subject_id), 2) AS insulin_final_rate,
  ROUND( (SUM(insulin_in_final) - SUM(insulin_initiated)) * 100.0 / COUNT(DISTINCT subject_id), 2) AS insulin_net_change_pp,

  -- Oral agents
  SUM(oral_initiated) AS oral_initiated_count,
  ROUND(SUM(oral_initiated) * 100.0 / COUNT(DISTINCT subject_id), 2) AS oral_initiation_rate,
  SUM(oral_in_final) AS oral_final_count,
  ROUND(SUM(oral_in_final) * 100.0 / COUNT(DISTINCT subject_id), 2) AS oral_final_rate,
  ROUND( (SUM(oral_in_final) - SUM(oral_initiated)) * 100.0 / COUNT(DISTINCT subject_id), 2) AS oral_net_change_pp
FROM patient_meds;