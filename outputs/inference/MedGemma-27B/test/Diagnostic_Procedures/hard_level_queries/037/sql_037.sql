WITH SepsisPatients AS (
  -- Identify patients with sepsis based on ICD-9 codes
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d.icd_code IN ('001', '001.0', '001.1', '001.2', '001.3', '001.4', '001.5', '001.6', '001.7', '001.8', '001.9', '462', '4;