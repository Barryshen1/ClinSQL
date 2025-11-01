WITH first_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.admission_type,
    a.insurance,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
)
SELECT 
  COUNT(DISTINCT a.hadm_id) AS admission_count
FROM first_admissions a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE 
  a.rn = 1
  AND a.gender = 'M'
  AND a.age_at_admission BETWEEN 43 AND 53
  AND a.admission_type = 'EMERGENCY'
  AND a.insurance = 'Medicare'
  AND d.seq_num = 1
  AND d.icd_version = 10
  AND d.icd_code IN (
    'E10.10', 'E10.11', 'E10.12', 'E10.13', 'E10.19',
    'E11.10', 'E11.11', 'E11.12', 'E11.13', 'E11.19'
  );