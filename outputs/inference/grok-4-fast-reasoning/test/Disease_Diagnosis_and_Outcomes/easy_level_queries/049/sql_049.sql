WITH stroke_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '436'))
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
        )
    )
)
SELECT 
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_hospital_los_days
FROM 
  stroke_admissions
WHERE 
  gender = 'F'
  AND age_at_admission BETWEEN 50 AND 60;