WITH cabg_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.subject_id = proc.subject_id AND a.hadm_id = proc.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND proc.icd_version = 9
    AND proc.seq_num = 1
    AND proc.icd_code LIKE '36.1%'
)
SELECT 
  AVG(i.los / 1440.0) AS mean_icu_los_days
FROM 
  cabg_admissions ca
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` i
  ON ca.subject_id = i.subject_id AND ca.hadm_id = i.hadm_id
WHERE 
  ca.rn = 1;