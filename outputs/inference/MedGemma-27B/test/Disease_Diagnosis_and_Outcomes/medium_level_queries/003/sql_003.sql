WITH PatientAge AS (
  SELECT
    subject_id,
    CASE
      WHEN anchor_age BETWEEN 44 AND 54 THEN 1
      ELSE 0
    END AS is_age_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
), StrokeDiagnosis AS (
  SELECT
    p.subject_id,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND d.icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') -- Ischemic stroke
    AND d.icd_version = '9'
), StrokeType AS (
  SELECT
    subject_id,
    CASE
      WHEN icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') THEN 'Ischemic'
      WHEN icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') THEN 'Hemorrhagic'
      ELSE 'Other'
    END AS stroke_type
  FROM StrokeDiagnosis
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN StrokeDiagnosis AS sd
    ON a.subject_id = sd.subject_id
), ICUStayInfo AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_hosp.icustays` AS s
  INNER JOIN AdmissionInfo AS ai
    ON s.subject_id = ai.subject_id
    AND s.hadm_id = ai.hadm_id
), Comorbidity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code NOT IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') -- Exclude stroke codes
    AND icd_code NOT IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') -- Exclude stroke codes
    AND icd_code NOT IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') -- Exclude stroke codes
    AND icd_code NOT IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') -- Exclude stroke codes
    AND icd_code NOT IN ('I60', 'I61', 'I6;