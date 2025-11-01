WITH base_cohort AS (
  -- Step 1: Identify male patients within the specified age range at admission
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at the time of hospital admission
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 46 AND 56
),

ami_patients AS (
  -- Step 2: Filter the cohort for patients with an Acute Myocardial Infarction diagnosis
  SELECT DISTINCT
    bc.subject_id,
    bc.hadm_id,
    bc.age_at_admission,
    bc.admittime,
    bc.dischtime,
    bc.hospital_expire_flag
  FROM
    base_cohort AS bc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON bc.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    d_dx.long_title LIKE '%Acute myocardial infarction%'
),

complication_codes AS (
  -- Step 3a: Define and identify major complications using ICD codes
  -- Cardiogenic shock
  SELECT hadm_id, 'cardiogenic_shock' AS complication FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code IN ('78551', 'R570')
  UNION ALL
  -- Ventricular fibrillation, flutter, and tachycardia
  SELECT hadm_id, 'ventricular_arrhythmia' AS complication FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code IN ('4275', 'I4901', '42742', 'I4902', '4271', 'I472')
  UNION ALL
  -- Acute Kidney Injury (AKI)
  SELECT hadm_id, 'aki' AS complication FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code IN ('5845', '5846', '5847', '5848', '5849', 'N170', 'N171', 'N172', 'N179')
  UNION ALL
  -- Stroke / CVA (using a title search for broader coverage)
  SELECT di.hadm_id, 'stroke' AS complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%Cerebral infarction%'
    OR d.long_title LIKE '%Intracerebral haemorrhage%'
    OR d.long_title LIKE '%Subarachnoid haemorrhage%'
  UNION ALL
  -- Mechanical Ventilation
  SELECT hadm_id, 'mech_vent' AS complication FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` WHERE icd_code IN ('9670', '9671', '9672', '5A1935Z', '5A1945Z', '5A1955Z')
),

num_complications AS (
  -- Step 3b: Count the number of distinct complication types per admission
  SELECT
    hadm_id,
    COUNT(DISTINCT complication) AS num_major_complications
  FROM
    complication_codes
  GROUP BY
    hadm_id
),

patient_data AS (
  -- Step 4: Combine AMI patient data with complication counts
  SELECT
    ap.hadm_id,
    ap.age_at_admission,
    ap.hospital_expire_flag,
    -- Calculate survivor length of stay in fractional days
    CASE
      WHEN ap.hospital_expire_flag = 0 THEN ROUND(DATETIME_DIFF(ap.dischtime, ap.admittime, HOUR) / 24, 2)
      ELSE NULL
    END AS survivor_los_days,
    -- Use COALESCE for patients with zero complications
    COALESCE(nc.num_major_complications, 0) AS num_major_complications
  FROM
    ami_patients AS ap
  LEFT JOIN
    num_complications AS nc
    ON ap.hadm_id = nc.hadm_id
),

risk_scores AS (
  -- Step 5: Calculate composite risk score and stratify into quintiles
  SELECT
    hadm_id,
    hospital_expire_flag,
    survivor_los_days,
    CASE WHEN num_major_complications > 0 THEN 1 ELSE 0 END AS had_major_complication,
    -- Composite Risk Score = Age + Number of Major Complications
    (age_at_admission + num_major_complications) AS composite_risk_score,
    -- Stratify into quintiles (5 groups) based on risk score
    NTILE(5) OVER (ORDER BY (age_at_admission + num_major_complications)) AS risk_quintile
  FROM
    patient_data
)

-- Step 6: Final aggregation to report metrics per quintile
SELECT
  risk_quintile,
  COUNT(hadm_id) AS num_patients,
  -- In-hospital mortality %
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  -- Major complication %
  ROUND(AVG(had_major_complication) * 100, 2) AS major_complication_pct,
  -- Median survivor LOS in days
  APPROX_QUANTILES(survivor_los_days, 100)[OFFSET(50)] AS median_survivor_los_days
FROM
  risk_scores
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;