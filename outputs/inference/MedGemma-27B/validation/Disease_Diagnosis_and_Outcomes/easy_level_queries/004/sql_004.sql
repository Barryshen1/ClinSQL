WITH RelevantPatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admission_type = 'EMERGENCY'
), DiagnosisPatients AS (
  SELECT
    rp.subject_id,
    rp.hadm_id,
    rp.admittime,
    rp.dischtime
  FROM RelevantPatients AS rp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON rp.subject_id = d.subject_id AND rp.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('250.00', '250.01', '250.02', '250.10', '250.11', '250.12', '250.13', '250.20', '250.21', '250.22', '250.23', '250.30', '250.31', '250.32', '250.33', '250.40', '250.41', '250.42', '250.43', '250.50', '250.51', '250.52', '250.53', '250.60', '250.61', '250.62', '250.63', '250.70', '250.71', '250.72', '250.73', '250.80', '250.81', '250.82', '250.83', '250.90', '250.91', '250.92', '250.93', 'E10.10', 'E10.11', 'E11.10', 'E11.11')
)
SELECT
  PERCENTILE_CONT(0.25, DATE_DIFF(dischtime, admittime, DAY)) AS percentile_25_los
FROM DiagnosisPatients;