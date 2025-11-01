WITH
-- Get female patients aged 44-54
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),

-- Get their admissions with intracranial hemorrhage
ich_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (d.icd_code LIKE '43%' OR d.icd_code LIKE 'I6%' OR d.icd_code LIKE 'S06%') -- ICH codes
    AND a.admission_type IN ('EMERGENCY', 'URGENT') -- Inpatient admissions
),

-- Calculate chronic conditions count
chronic_conditions AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS chronic_condition_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_code LIKE '250%' OR -- Diabetes
     d.icd_code LIKE '401%' OR -- Hypertension
     d.icd_code LIKE '414%' OR -- CAD
     d.icd_code LIKE '428%' OR -- CHF
     d.icd_code LIKE '496%' OR -- COPD
     d.icd_code LIKE '585%' OR -- CKD
     d.icd_code LIKE 'E11%' OR -- Diabetes (ICD-10)
     d.icd_code LIKE 'I10%' OR -- Hypertension (ICD-10)
     d.icd_code LIKE 'I25%' OR -- CAD (ICD-10)
     d.icd_code LIKE 'I50%' OR -- CHF (ICD-10)
     d.icd_code LIKE 'J44%' OR -- COPD (ICD-10)
     d.icd_code LIKE 'N18%')    -- CKD (ICD-10)
    AND EXISTS (
      SELECT 1 FROM ich_admissions ia
      WHERE d.subject_id = ia.subject_id AND d.hadm_id = ia.hadm_id
    )
  GROUP BY
    subject_id, hadm_id
),

-- Get first GCS score
first_gcs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.valuenum AS gcs_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'Glasgow Coma Scale Total'
    AND EXISTS (
      SELECT 1 FROM ich_admissions ia
      WHERE ce.subject_id = ia.subject_id AND ce.hadm_id = ia.hadm_id
    )
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id, ce.hadm_id ORDER BY ce.charttime) = 1
),

-- Get first INR value
first_inr AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS inr_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'INR(PT)'
    AND EXISTS (
      SELECT 1 FROM ich_admissions ia
      WHERE le.subject_id = ia.subject_id AND le.hadm_id = ia.hadm_id
    )
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) = 1
),

-- Calculate composite risk score
risk_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.hospital_los_hours,
    COALESCE(cc.chronic_condition_count, 0) AS chronic_condition_count,
    COALESCE(g.gcs_score, 15) AS gcs_score, -- Default to 15 if missing
    COALESCE(i.inr_value, 1.0) AS inr_value, -- Default to 1.0 if missing
    -- Composite score calculation (example weights)
    (COALESCE(cc.chronic_condition_count, 0) * 2) +
    (15 - COALESCE(g.gcs_score, 15)) * 3 +
    (COALESCE(i.inr_value, 1.0) - 1.0) * 5 AS composite_score
  FROM
    ich_admissions a
  LEFT JOIN
    chronic_conditions cc
    ON a.subject_id = cc.subject_id AND a.hadm_id = cc.hadm_id
  LEFT JOIN
    first_gcs g
    ON a.subject_id = g.subject_id AND a.hadm_id = g.hadm_id
  LEFT JOIN
    first_inr i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),

-- Calculate quartiles
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    composite_score,
    hospital_expire_flag,
    hospital_los_hours,
    NTILE(4) OVER (ORDER BY composite_score) AS quartile
  FROM
    risk_scores
),

-- Identify cardiac complications
cardiac_complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE
      WHEN d.icd_code LIKE '410%' OR -- AMI
           d.icd_code LIKE '411%' OR -- Other acute ischemic heart disease
           d.icd_code LIKE '427%' OR -- Cardiac dysrhythmias
           d.icd_code LIKE 'I21%' OR -- AMI (ICD-10)
           d.icd_code LIKE 'I22%' OR -- Subsequent AMI (ICD-10)
           d.icd_code LIKE 'I48%'     -- Atrial fibrillation/flutter (ICD-10)
      THEN 1 ELSE 0 END) AS has_cardiac_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    EXISTS (
      SELECT 1 FROM quartiles q
      WHERE d.subject_id = q.subject_id AND d.hadm_id = q.hadm_id
    )
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Identify neurologic complications
neurologic_complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE
      WHEN d.icd_code LIKE '433%' OR -- Occlusion of cerebral arteries
           d.icd_code LIKE '434%' OR -- Other cerebral artery occlusion
           d.icd_code LIKE '436%' OR -- Acute cerebrovascular disease
           d.icd_code LIKE 'I63%' OR -- Cerebral infarction (ICD-10)
           d.icd_code LIKE 'I67%'     -- Other cerebrovascular diseases (ICD-10)
      THEN 1 ELSE 0 END) AS has_neurologic_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    EXISTS (
      SELECT 1 FROM quartiles q
      WHERE d.subject_id = q.subject_id AND d.hadm_id = q.hadm_id
    )
  GROUP BY
    d.subject_id, d.hadm_id
)

-- Final results
SELECT
  q.quartile,
  COUNT(DISTINCT q.subject_id) AS patient_count,
  SUM(q.hospital_expire_flag) AS in_hospital_mortality_count,
  ROUND(SUM(q.hospital_expire_flag) * 100.0 / COUNT(DISTINCT q.subject_id), 1) AS in_hospital_mortality_rate,
  SUM(cc.has_cardiac_complication) AS cardiac_complication_count,
  ROUND(SUM(cc.has_cardiac_complication) * 100.0 / COUNT(DISTINCT q.subject_id), 1) AS cardiac_complication_rate,
  SUM(nc.has_neurologic_complication) AS neurologic_complication_count,
  ROUND(SUM(nc.has_neurologic_complication) * 100.0 / COUNT(DISTINCT q.subject_id), 1) AS neurologic_complication_rate,
  ROUND(PERCENTILE_CONT(q.hospital_los_hours / 24.0, 0.5) OVER (PARTITION BY q.quartile), 1) AS median_los_days_survivors
FROM
  quartiles q
LEFT JOIN
  cardiac_complications cc
  ON q.subject_id = cc.subject_id AND q.hadm_id = cc.hadm_id
LEFT JOIN
  neurologic_complications nc
  ON q.subject_id = nc.subject_id AND q.hadm_id = nc.hadm_id
WHERE
  q.hospital_expire_flag = 0
GROUP BY
  q.quartile
ORDER BY
  q.quartile;