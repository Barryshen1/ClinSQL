WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),
pneumonia_patients AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON fa.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    fa.rn = 1
    AND di.seq_num = 1
    AND LOWER(d.long_title) LIKE '%pneumonia%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
)
SELECT
  ROUND(
    100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),
    2
  ) AS in_hospital_mortality_percent
FROM
  pneumonia_patients;