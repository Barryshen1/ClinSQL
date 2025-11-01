SELECT STDDEV(hospital_los) AS sd_hospital_los
FROM (
  SELECT 
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431'))
      OR 
      (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%'))
    )
)
WHERE age_at_admission BETWEEN 43 AND 53;