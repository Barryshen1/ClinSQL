WITH relevant_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type = 'EMERGENCY'
    AND d.icd_code IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25') -- Ischemic heart disease/ACS codes
    AND d.seq_num = 1 -- Consider the primary diagnosis
)
SELECT
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS average_hospital_los
FROM
  relevant_patients;