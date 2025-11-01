WITH stroke_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    IFNULL(
      DATE_DIFF(
        COALESCE(a.dischtime, a.deathtime), 
        a.admittime, 
        DAY
      ), 0
    ) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.hadm_id = d.hadm_id 
    AND d.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON 
    d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'
    AND a.hospital_expire_flag = 0
)

SELECT 
  PERCENTILE_CONT(los_days, 0.25) AS p25_los_days
FROM 
  stroke_cohort
WHERE 
  los_days >= 1;