WITH relevant_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.icd_code IN ('I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'J44.9', 'J45.909', 'J45.901', 'J45.902', 'J45.903', 'J45.904', 'J45.905', 'J45.906', 'J45.908')
)
SELECT
  STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_hospital_los
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN
  relevant_patients AS rp
  ON a.hadm_id = rp.hadm_id;