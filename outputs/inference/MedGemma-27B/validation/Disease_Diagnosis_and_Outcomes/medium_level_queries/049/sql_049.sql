WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
), ComorbidityInfo AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM
    DiagnosisInfo
  WHERE
    icd_code IN ('I21', 'I25', 'I20', 'E11', 'E10', 'E13', 'E14') -- STEMI, NSTEMI, Angina, Diabetes
  GROUP BY
    hadm_id
), CKDInfo AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS ckd_count
  FROM
    DiagnosisInfo
  WHERE
    icd_code IN ('N18', 'N19', 'I12', 'I13', 'E87') -- CKD codes
  GROUP BY
    hadm_id
), DiabetesInfo AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS diabetes_count
  FROM
    DiagnosisInfo
  WHERE
    icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
  GROUP BY
    hadm_id
), CombinedInfo AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(ckd.ckd_count, 0) AS ckd_count,
    COALESCE(d.diabetes_count, 0) AS diabetes_count
  FROM
    AdmissionInfo AS a
    JOIN PatientInfo AS p ON a.subject_id = p.subject_id
    LEFT JOIN ComorbidityInfo AS c ON a.hadm_id = c.hadm_id
    LEFT JOIN CKDInfo AS ckd ON a.hadm_id = ckd.hadm_id
    LEFT JOIN DiabetesInfo AS d ON a.hadm_id = d.hadm_id
)
SELECT
  CASE
    WHEN ci.comorbidity_count BETWEEN 0 AND 1
    THEN '0-1'
    WHEN ci.comorbidity_count >= 2
    THEN '>=2' -- Changed to >=2 to match the case statement
    ELSE 'Unknown'
  END AS comorbidity_group,
  CASE
    WHEN ci.ckd_count > 0
    THEN 'Yes'
    ELSE 'No'
  END AS ckd_prevalence,
  CASE
    WHEN ci.diabetes_count > 0
    THEN 'Yes'
    ELSE 'No'
  END AS diabetes_pre;