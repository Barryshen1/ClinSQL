SELECT PERCENTILE_CONT(los, 0.25) AS percentile_25
FROM (
  SELECT 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 50 AND 60
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
) subquery;