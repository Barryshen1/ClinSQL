SELECT 
  AVG((UNIX_SECONDS(TIMESTAMP(a.dischtime)) - UNIX_SECONDS(TIMESTAMP(a.admittime))) / (24*60*60.0)) AS avg_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
WHERE 
  p.gender = 'F'
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '412%' OR d.icd_code LIKE '413%' OR d.icd_code LIKE '414%'))
    OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%'))
  )
  AND a.dischtime IS NOT NULL
  AND a.admittime IS NOT NULL
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88;