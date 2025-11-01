WITH
-- Get female patients aged 76-86
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get pneumonia admissions (using common pneumonia ICD codes)
pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%' OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J18%')
),

-- Get medication complexity (unique drugs in first 7 days)
medication_complexity AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs_first_7_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN pneumonia_admissions pa ON p.hadm_id = pa.hadm_id
  WHERE TIMESTAMP_DIFF(p.starttime, pa.admittime, DAY) <= 7
  GROUP BY p.hadm_id
),

-- Create tertiles for medication complexity
tertiles AS (
  SELECT
    hadm_id,
    unique_drugs_first_7_days,
    NTILE(3) OVER (ORDER BY unique_drugs_first_7_days) AS tertile
  FROM medication_complexity
),

-- Calculate 30-day readmission flag
readmissions AS (
  SELECT
    a1.hadm_id AS original_hadm_id,
    a1.subject_id,
    a1.dischtime,
    a2.hadm_id AS readmission_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id AND a1.hadm_id < a2.hadm_id
  WHERE a1.hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
    AND TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) BETWEEN 1 AND 30
),

-- Final aggregation
final_results AS (
  SELECT
    t.tertile,
    COUNT(DISTINCT pa.hadm_id) AS admission_count,
    MIN(mc.unique_drugs_first_7_days) AS min_medication_complexity,
    AVG(mc.unique_drugs_first_7_days) AS avg_medication_complexity,
    MAX(mc.unique_drugs_first_7_days) AS max_medication_complexity,
    AVG(pa.los_days) AS avg_los,
    SUM(CASE WHEN pa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT pa.hadm_id) AS in_hospital_mortality_pct,
    SUM(CASE WHEN r.original_hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT pa.hadm_id) AS readmission_30day_pct
  FROM tertiles t
  JOIN medication_complexity mc ON t.hadm_id = mc.hadm_id
  JOIN pneumonia_admissions pa ON t.hadm_id = pa.hadm_id
  LEFT JOIN readmissions r ON t.hadm_id = r.original_hadm_id
  GROUP BY t.tertile
)

SELECT * FROM final_results
ORDER BY tertile;