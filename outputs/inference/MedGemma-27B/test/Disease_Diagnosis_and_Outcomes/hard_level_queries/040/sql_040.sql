WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), DiagnosisInfo AS (
  SELECT
    subject_id,
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code LIKE '430%'
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), CombinedInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.los,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM
    AdmissionInfo AS a
  INNER JOIN
    PatientInfo AS p ON a.subject_id = p.subject_id
  INNER JOIN
    DiagnosisInfo AS d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND d.icd_code LIKE '430%'
), RiskScoreCalculation AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    los,
    gender,
    anchor_age,
    -- Calculate the composite risk score here
    -- This is a placeholder for the actual risk score calculation
    -- Replace this with the actual calculation based on the available data
    -- For example, you might use age, gender, admission type, etc.
    -- Let's assume a simple score for demonstration purposes
    (anchor_age * 0.1 + CASE WHEN gender = 'F' THEN 1 ELSE 0 END + CASE WHEN admission_type = 'EMERGENCY' THEN 1 ELSE 0 END) AS composite_risk_score
  FROM
    CombinedInfo
), QuintileCalculation AS (
  SELECT
    hadm_id,
    subject_id,
    composite_risk_score,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    los,
    gender,
    anchor_age,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM
    RiskScoreCalculation
), FinalResults AS (
  SELECT
    risk_quintile,
    COUNT(hadm_id) AS n,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS mortality_percent,
    -- Placeholder for major complication calculation
    -- Replace this with the actual calculation based on the available data
    -- For example, you might use diagnoses or procedures
    0 AS major_complication_percent,
    AVG(los) AS median_survivor_los
  FROM
    QuintileCalculation
  WHERE
    hospital_expire_flag = 0 -- Only include survivors for median LOS calculation
  GROUP BY
    risk_quintile
)
SELECT
  risk_quintile,
  n,
  mortality_percent,
  major_complication_percent,
  median_survivor_los
FROM
  FinalResults
ORDER BY
  risk_quintile;