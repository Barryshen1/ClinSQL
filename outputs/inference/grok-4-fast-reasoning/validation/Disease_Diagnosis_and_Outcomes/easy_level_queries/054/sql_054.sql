WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.gender, 
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.dischtime > a.admittime
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = '10' 
           AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
          OR
          (d.icd_version = '9' 
           AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
        )
    )
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  cohort
WHERE 
  los_days > 0;