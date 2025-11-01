WITH eligible_admissions AS (
  SELECT
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    -- Male patients
    p.gender = 'M'
    -- Age 72-82 at admission (approximate, since anchor_age is at anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 72 AND 82
    -- Medicare insurance
    AND a.insurance = 'Medicare'
    -- Transferred from another hospital
    AND a.admission_type = 'TRANSFER'
    -- Unstable angina as principal diagnosis (ICD-9: 411.1 or ICD-10: I20.0)
    AND d.seq_num = 1  -- Principal diagnosis
    AND (d.icd_code = '4111' OR d.icd_code = 'I200')  -- ICD-9 or ICD-10 codes
    -- Discharge recorded
    AND a.dischtime IS NOT NULL
)

SELECT
  COUNT(DISTINCT hadm_id) AS total_admissions
FROM
  eligible_admissions;