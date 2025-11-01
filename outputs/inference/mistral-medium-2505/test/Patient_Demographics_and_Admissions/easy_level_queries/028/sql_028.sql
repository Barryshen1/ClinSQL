WITH sepsis_patients AS (
  -- Get male patients aged 90-100 with sepsis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (d.icd_code LIKE 'A41.%' OR d.icd_code LIKE 'R65.%')
)

SELECT
  STDDEV(icu.los) AS stddev_icu_los_days
FROM
  sepsis_patients sp
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON sp.hadm_id = icu.hadm_id
WHERE
  icu.los IS NOT NULL;