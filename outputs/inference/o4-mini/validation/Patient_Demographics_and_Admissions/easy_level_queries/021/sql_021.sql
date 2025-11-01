WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),
pneumonia_first_adm AS (
  -- Filter to first admission and join pneumonia diagnoses
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  WHERE
    fa.rn = 1
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = fa.subject_id
        AND d.hadm_id = fa.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
)
SELECT
  COUNTIF(hospital_expire_flag = 1) AS num_deaths,
  COUNT(*) AS total_patients,
  ROUND(100.0 * COUNTIF(hospital_expire_flag = 1) / COUNT(*), 2) AS mortality_percent
FROM
  pneumonia_first_adm;