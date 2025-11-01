WITH female_copd_patients AS (
  -- Get female patients with COPD diagnosis
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J43%')
),

creatinine_values AS (
  -- Get all serum creatinine measurements for these patients
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS creatinine_mg_dL
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN female_copd_patients f ON l.subject_id = f.subject_id
  WHERE l.itemid = 50912  -- Serum creatinine
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0  -- Filter out invalid values
)

-- Get the maximum peak serum creatinine for each patient
SELECT
  subject_id,
  MAX(creatinine_mg_dL) AS max_peak_serum_creatinine_mg_dL
FROM creatinine_values
GROUP BY subject_id
ORDER BY max_peak_serum_creatinine_mg_dL DESC;