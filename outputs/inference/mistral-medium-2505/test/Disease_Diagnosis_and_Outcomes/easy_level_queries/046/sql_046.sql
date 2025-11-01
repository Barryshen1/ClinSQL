WITH hemorrhagic_stroke_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 10 AND di.icd_code LIKE 'I61%')  -- ICD-10 hemorrhagic stroke
      OR
      (d.icd_version = 9 AND di.icd_code LIKE '431%')   -- ICD-9 hemorrhagic stroke
    )
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

SELECT
  STDDEV(los_days) AS stddev_hospital_los_days
FROM
  hemorrhagic_stroke_patients;