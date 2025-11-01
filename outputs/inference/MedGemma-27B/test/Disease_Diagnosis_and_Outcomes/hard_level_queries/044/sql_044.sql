WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 59 AND 69
), AdmissionInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
), DiagnosisInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM
    AdmissionInfo AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I46%' -- Cardiac arrest code
), RiskScore AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(d.icd_code) AS num_comorbidities
  FROM
    DiagnosisInfo AS d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code = di.icd_code AND di.icd_version = 9
  WHERE
    di.long_title LIKE '%heart failure%' OR di.long_title LIKE '%coronary artery disease%' OR di.long_title LIKE '%hypertension%' OR di.long_title LIKE '%diabetes%' OR di.long_title LIKE '%chronic kidney disease%'
  GROUP BY
    d.subject_id,
    d.hadm_id
), Quartile AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    rs.num_comorbidities,
    NTILE(4) OVER (ORDER BY rs.num_comorbidities) AS risk_quartile
  FROM
    AdmissionInfo AS a
    INNER JOIN RiskScore AS rs
      ON a.subject_id = rs.subject_id AND a.hadm_id = rs.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM DiagnosisInfo)
), Mortality AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quartile,
    CASE
      WHEN q.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality_30_day
  FROM
    Quartile AS q
  WHERE
    DATE_DIFF(q.deathtime, q.admittime, DAY) <= 30
), Complication AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quartile,
    CASE
      WHEN d.icd_code LIKE '%stroke%' THEN 1
      ELSE 0
    END AS neurologic_complication,
    CASE
      WHEN d.icd_code LIKE '%myocardial infarction%' OR d.icd_code LIKE '%heart failure%' THEN 1
      ELSE 0
    END AS cardiovascular_complication
  FROM
    Quartile AS q
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON q.subject_id = d.subject_id AND q.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE '%stroke%' OR d.icd_code LIKE '%myocardial infarction%' OR d.icd_code LIKE '%heart failure%'
), LOS AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quart;