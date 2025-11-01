SELECT COUNT(DISTINCT a.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
  AND d.seq_num = 1  -- principal diagnosis
WHERE 
  p.gender = 'M'  -- male
  AND a.insurance = 'Medicare'  -- Medicare insurance
  AND a.admission_type = 'transfer from another hospital'  -- admission type
  AND ( 
        (d.icd_code = '585.6' AND d.icd_version = 9) 
        OR 
        (d.icd_code = 'N18.6' AND d.icd_version = 10)
      )
  AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR) BETWEEN 90 AND 100;