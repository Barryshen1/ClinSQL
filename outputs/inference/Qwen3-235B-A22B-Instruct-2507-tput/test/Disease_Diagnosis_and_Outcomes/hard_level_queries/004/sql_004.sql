WITH age_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND a.admission_type IN ('Elective', 'Urgent', 'Emergency')
),
icd_hemorrhage AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND d.long_title LIKE '%intracranial hemorrhage%'
    AND SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61', 'I62')
),
comorbidity_definitions AS (
  SELECT 'hypertension' AS condition, 'I10' AS code_start, 'I15' AS code_end UNION ALL
  SELECT 'diabetes', 'E11', 'E14' UNION ALL
  SELECT 'atrial_fibrillation', 'I48', 'I48' UNION ALL
  SELECT 'heart_failure', 'I50', 'I50' UNION ALL
  SELECT 'ckd', 'N18', 'N18' UNION ALL
  SELECT 'copd', 'J44', 'J44' UNION ALL
  SELECT 'cancer', 'C00', 'C97' UNION ALL
  SELECT 'obesity', 'E66', 'E66' UNION ALL
  SELECT 'liver_disease', 'I86', 'I86' UNION ALL
  SELECT 'peripheral_vascular_disease', 'I70', 'I79'
),
comorbidity_flagged AS (
  SELECT
    af.*
  FROM age_filtered af
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON af.hadm_id = di.hadm_id
  INNER JOIN comorbidity_definitions cd
    ON di.icd_version = 10
    AND di.icd_code >= cd.code_start
    AND di.icd_code <= cd.code_end
  WHERE NOT (SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61', 'I62')) -- Exclude hemorrhage codes
),
comorbidity_count AS (
  SELECT
    subject_id,
    hadm_id,
    gender,
    age_at_admit,
    admittime,
    dischtime,
    hospital_expire_flag,
    COUNT(DISTINCT condition) AS comorbidity_score
  FROM comorbidity_flagged
  GROUP BY subject_id, hadm_id, gender, age_at_admit, admittime, dischtime, hospital_expire_flag
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY comorbidity_score) AS risk_quartile
  FROM comorbidity_count
),
complications AS (
  SELECT
    q.*,
    -- Cardiac complications: MI, cardiac arrest, AF, HF
    MAX(CASE WHEN d.long_title LIKE '%myocardial infarction%' OR
                  d.long_title LIKE '%cardiac arrest%' OR
                  d.long_title LIKE '%atrial fibrillation%' OR
                  d.long_title LIKE '%heart failure%'
             THEN 1 ELSE 0 END) AS has_cardiac_complication,
    -- Neurologic complications: seizure, ischemic stroke, brain death, hydrocephalus
    MAX(CASE WHEN d.long_title LIKE '%seizure%' OR
                  d.long_title LIKE '%epilepsy%' OR
                  d.long_title LIKE '%ischemic stroke%' OR
                  d.long_title LIKE '%hydrocephalus%' OR
                  d.long_title LIKE '%cerebral edema%'
             THEN 1 ELSE 0 END) AS has_neuro_complication
  FROM quartiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON q.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY q.subject_id, q.hadm_id, q.gender, q.age_at_admit, q.admittime, q.dischtime, q.hospital_expire_flag, q.comorbidity_score, q.risk_quartile
),
los_survivors AS (
  SELECT
    risk_quartile,
    APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0, 100)[OFFSET(50)] AS median_los_days
  FROM complications
  WHERE hospital_expire_flag = 0
  GROUP BY risk_quartile
),
los_all AS (
  SELECT
    risk_quartile,
    COUNT(*) AS patient_count,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate,
    AVG(has_cardiac_complication) AS cardiac_complication_rate,
    AVG(has_neuro_complication) AS neuro_complication_rate
  FROM complications
  GROUP BY risk_quartile
)
SELECT
  la.risk_quartile,
  la.patient_count,
  la.mortality_rate,
  la.cardiac_complication_rate,
  la.neuro_complication_rate,
  COALESCE(ls.median_los_days, 0) AS median_los_survivors_days
FROM los_all la
LEFT JOIN los_survivors ls
  ON la.risk_quartile = ls.risk_quartile
ORDER BY la.risk_quartile;