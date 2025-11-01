WITH patient_data AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_code IN ('J44.51', 'J44.52', 'J44.59')
    )
)
SELECT 
  PERCENTILE_CONT(hospital_los, 0.25) AS los_25th_percentile
FROM 
  patient_data;