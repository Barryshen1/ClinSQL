WITH pneumonia_admissions AS (
  -- Get admissions with pneumonia diagnoses for females aged 49-59
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      -- ICD-10 codes for pneumonia (J12-J18)
      (d.icd_version = 10 AND d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%' OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%' OR d.icd_code LIKE 'J18%')
      OR
      -- ICD-9 codes for pneumonia (480-486)
      (d.icd_version = 9 AND d.icd_code BETWEEN '480' AND '486')
    )
    AND a.dischtime IS NOT NULL
)

-- Calculate the 25th percentile LOS
SELECT
  APPROX_QUANTILES(length_of_stay_days, 4)[OFFSET(1)] AS percentile_25_los_days
FROM
  pneumonia_admissions;