SELECT 
  STDDEV_POP(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
  ) AS sd_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
USING (subject_id)
JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
USING (subject_id, hadm_id)
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 
     AND REGEXP_CONTAINS(d.icd_code, r'^(430|431|432)'))
    OR
    (d.icd_version = 10 
     AND REGEXP_CONTAINS(UPPER(d.icd_code), r'^(I60|I61|I62)'))
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;