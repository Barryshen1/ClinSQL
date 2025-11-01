WITH dka_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE d.seq_num = 1
    AND d.icd_code IN ('25010', '25011', '25012', '25013', 'E1010', 'E1011', 'E1110', 'E1111')
)
SELECT COUNT(*)
FROM dka_admissions
WHERE admission_seq = 1
  AND gender = 'M'
  AND insurance = 'Medicare'
  AND admission_location = 'EMERGENCY ROOM ADMIT'
  AND (anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)) BETWEEN 43 AND 53;