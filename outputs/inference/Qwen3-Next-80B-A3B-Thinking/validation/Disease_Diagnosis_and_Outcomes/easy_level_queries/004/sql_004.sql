SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS percentile_25
FROM (
  SELECT 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
    AND d.seq_num = 1
    AND (di.long_title LIKE '%ketoacidosis%' 
         OR di.long_title LIKE '%hyperosmolar%' 
         OR di.long_title LIKE '%hyperglycemic hyperosmolar state%')
) subquery;