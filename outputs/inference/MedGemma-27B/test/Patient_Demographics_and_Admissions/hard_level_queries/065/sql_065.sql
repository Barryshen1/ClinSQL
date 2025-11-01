WITH PatientAdmissionDiagnosis AS (
  SELECT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.discharge_location NOT IN ('DIED', 'HOME')
    AND a.hospital_expire_flag = 0
    AND d.icd_code = '414.1'
    AND d.seq_num = 1
)
SELECT
  COUNT(hadm_id)
FROM PatientAdmissionDiagnosis;