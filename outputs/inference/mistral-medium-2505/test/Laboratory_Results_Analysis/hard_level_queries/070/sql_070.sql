WITH
-- Define hemorrhagic stroke ICD-10 codes
hemorrhagic_stroke_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I61.%'
),

-- Get male patients aged 40-50 with hemorrhagic stroke
stroke_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN hemorrhagic_stroke_codes hsc ON d.icd_code = hsc.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Get general male inpatients aged 40-50 without hemorrhagic stroke
general_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND p.subject_id NOT IN (SELECT subject_id FROM stroke_patients)
),

-- Get abnormal labs within 72 hours of admission for stroke patients
stroke_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    COUNT(DISTINCT l.itemid) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN stroke_patients sp ON l.subject_id = sp.subject_id AND l.hadm_id = sp.hadm_id
  WHERE l.charttime BETWEEN sp.admittime AND TIMESTAMP_ADD(sp.admittime, INTERVAL 72 HOUR)
    AND (
      (l.valuenum < l.ref_range_lower AND l.ref_range_lower IS NOT NULL) OR
      (l.valuenum > l.ref_range_upper AND l.ref_range_upper IS NOT NULL)
    )
  GROUP BY l.subject_id, l.hadm_id, l.itemid
),

-- Get abnormal labs within 72 hours of admission for general patients
general_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    COUNT(DISTINCT l.itemid) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN general_patients gp ON l.subject_id = gp.subject_id AND l.hadm_id = gp.hadm_id
  WHERE l.charttime BETWEEN gp.admittime AND TIMESTAMP_ADD(gp.admittime, INTERVAL 72 HOUR)
    AND (
      (l.valuenum < l.ref_range_lower AND l.ref_range_lower IS NOT NULL) OR
      (l.valuenum > l.ref_range_upper AND l.ref_range_upper IS NOT NULL)
    )
  GROUP BY l.subject_id, l.hadm_id, l.itemid
),

-- Calculate lab instability score (count of unique abnormal labs) for stroke patients
stroke_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT itemid) AS lab_instability_score
  FROM stroke_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate lab instability score for general patients
general_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT itemid) AS lab_instability_score
  FROM general_labs
  GROUP BY subject_id, hadm_id
),

-- Add quartile stratification for stroke patients
stroke_with_quartiles AS (
  SELECT
    s.*,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM stroke_scores s
),

-- Add quartile stratification for general patients
general_with_quartiles AS (
  SELECT
    g.*,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM general_scores g
)

-- Final results
SELECT
  'Stroke Patients' AS cohort,
  swq.quartile,
  COUNT(DISTINCT swq.subject_id) AS patient_count,
  AVG(sp.los_hours) AS avg_los_hours,
  SUM(sp.hospital_expire_flag) / COUNT(DISTINCT swq.subject_id) AS mortality_rate,
  AVG(swq.lab_instability_score) AS avg_abnormal_labs
FROM stroke_with_quartiles swq
JOIN stroke_patients sp ON swq.subject_id = sp.subject_id AND swq.hadm_id = sp.hadm_id
GROUP BY swq.quartile

UNION ALL

SELECT
  'General Patients' AS cohort,
  gwq.quartile,
  COUNT(DISTINCT gwq.subject_id) AS patient_count,
  AVG(gp.los_hours) AS avg_los_hours,
  SUM(gp.hospital_expire_flag) / COUNT(DISTINCT gwq.subject_id) AS mortality_rate,
  AVG(gwq.lab_instability_score) AS avg_abnormal_labs
FROM general_with_quartiles gwq
JOIN general_patients gp ON gwq.subject_id = gp.subject_id AND gwq.hadm_id = gp.hadm_id
GROUP BY gwq.quartile

ORDER BY cohort, quartile;