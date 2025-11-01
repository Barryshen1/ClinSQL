WITH PatientInfo AS (
  -- Select patient demographics and admission details
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89
), DiagnosisInfo AS (
  -- Select diagnoses for patients
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'I26.99' -- Pulmonary embolism code
), ComorbidityInfo AS (
  -- Calculate comorbidity burden for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code NOT IN ('I26.99') -- Exclude PE code
  GROUP BY
    a.subject_id,
    a.hadm_id
), ComorbidityRank AS (
  -- Rank patients based on comorbidity burden
  SELECT
    subject_id,
    hadm_id,
    comorbidity_count,
    PERCENT_RANK() OVER (ORDER BY comorbidity_count DESC) AS comorbidity_rank
  FROM ComorbidityInfo
), PatientComorbidity AS (
  -- Combine patient info, diagnosis info, and comorbidity rank
  SELECT
    pi.subject_id,
    pi.gender,
    pi.anchor_age,
    pi.admittime,
    pi.dischtime,
    pi.deathtime,
    pi.hospital_expire_flag,
    di.hadm_id,
    cr.comorbidity_count,
    cr.comorbidity_rank
  FROM PatientInfo AS pi
  INNER JOIN DiagnosisInfo AS di
    ON pi.subject_id = di.subject_id
  INNER JOIN ComorbidityRank AS cr
    ON pi.subject_id = cr.subject_id AND di.hadm_id = cr.hadm_id
  WHERE
    cr.comorbidity_rank <= 0.25 -- Top quartile comorbidity burden
), Mortality AS (
  -- Calculate 30-day mortality
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN deathtime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS mortality_30_day
  FROM PatientComorbidity
), Complications AS (
  -- Calculate complication rates
  SELECT
    subject_id,
    hadm_id,
    COUNT(CASE WHEN d.icd_code IN ('I21.9', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9') THEN 1 END) AS cardiac_complications,
    COUNT(CASE WHEN d.icd_code IN ('I63.9', 'I63.0', 'I63.1', 'I63.2', 'I63.3', 'I63.4', 'I63;