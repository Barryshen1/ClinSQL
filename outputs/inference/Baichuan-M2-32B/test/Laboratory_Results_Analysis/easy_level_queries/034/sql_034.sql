WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND icd_code IN (
        'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.81', 'I50.82', 'I50.89'
      )
  ) hf ON a.hadm_id = hf.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 65
)
SELECT MIN(l.valuenum) AS min_sodium
FROM eligible_admissions e
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
  ON e.hadm_id = l.hadm_id
  AND l.itemid = 50809
  AND l.charttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
  AND l.valuenum IS NOT NULL;