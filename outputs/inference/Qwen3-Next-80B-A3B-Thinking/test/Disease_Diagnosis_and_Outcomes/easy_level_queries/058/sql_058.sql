SELECT APPROX_QUANTILES(los, 100)[OFFSET(75)] AS percentile_75
FROM (
  SELECT DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 37 AND 47
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432')) OR
      (d.icd_version = 10 AND d.icd_code IN ('I60', 'I61', 'I62'))
    )
    AND a.dischtime IS NOT NULL
) subquery;