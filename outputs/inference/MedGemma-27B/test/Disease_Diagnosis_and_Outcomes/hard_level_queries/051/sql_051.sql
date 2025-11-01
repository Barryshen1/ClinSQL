WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 35 AND 45
), DiagnosisInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(d.icd_code) AS diagnosis_count
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  GROUP BY
    p.subject_id,
    p.hadm_id
), ComplicationInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(CASE WHEN m.test_name LIKE '%culture%' THEN 1 ELSE 0 END) AS culture_flag,
    COUNT(CASE WHEN m.test_name LIKE '%antibiotic%' THEN 1 ELSE 0 END) AS antibiotic_flag,
    COUNT(CASE WHEN m.interpretation = 'S' THEN 1 ELSE 0 END) AS susceptible_flag,
    COUNT(CASE WHEN m.interpretation = 'I' THEN 1 ELSE 0 END) AS intermediate_flag,
    COUNT(CASE WHEN m.interpretation = 'R' THEN 1 ELSE 0 END) AS resistant_flag
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` AS m
      ON p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
  GROUP BY
    p.subject_id,
    p.hadm_id
), RiskScore AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.diagnosis_count,
    ci.culture_flag + ci.antibiotic_flag + ci.susceptible_flag + ci.intermediate_flag + ci.resistant_flag AS major_complication_flags
  FROM
    DiagnosisInfo AS di
    INNER JOIN ComplicationInfo AS ci
      ON di.subject_id = ci.subject_id AND di.hadm_id = ci.hadm_id
), PatientRiskScore AS (
  SELECT
    rs.subject_id,
    rs.hadm_id,
    rs.diagnosis_count + 5 * rs.major_complication_flags AS risk_score
  FROM
    RiskScore AS rs
), Quartile AS (
  SELECT
    prs.subject_id,
    prs.hadm_id,
    prs.risk_score,
    NTILE(4) OVER (ORDER BY prs.risk_score) AS risk_quartile
  FROM
    PatientRiskScore AS prs
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime - a.admittime AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a;