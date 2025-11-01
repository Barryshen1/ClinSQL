WITH filtered_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      d.icd_code LIKE 'I20%' OR  -- Ischemic heart disease
      d.icd_code LIKE 'I21%' OR  -- Acute myocardial infarction (ACS)
      d.icd_code LIKE 'I22%' OR  -- Subsequent myocardial infarction
      d.icd_code LIKE 'I23%' OR  -- Certain current complications following acute myocardial infarction
      d.icd_code LIKE 'I24%' OR  -- Other acute ischemic heart diseases
      d.icd_code LIKE 'I25%'     -- Chronic ischemic heart disease
    )
)

SELECT
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24) AS avg_hospital_los_days
FROM
  filtered_patients;