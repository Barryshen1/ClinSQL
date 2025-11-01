WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    d.icd_code,
    d.icd_version,
    di.long_title,
    EXTRACT(YEAR FROM a.admittime) AS admission_year,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'K85.%')  -- ICD-10 code for acute pancreatitis
      OR (d.icd_version = 9 AND d.icd_code = '577.0')   -- ICD-9 code for acute pancreatitis
    )
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
)

SELECT
  COUNT(DISTINCT hadm_id) AS number_of_index_admissions
FROM
  index_admissions;