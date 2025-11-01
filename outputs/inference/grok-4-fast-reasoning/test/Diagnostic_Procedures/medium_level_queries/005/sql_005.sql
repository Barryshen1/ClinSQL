WITH stroke_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '436'))
     OR (icd_version = 10 AND icd_code LIKE 'I63%')
),
stroke_classification AS (
  SELECT 
    sh.subject_id, 
    sh.hadm_id,
    CASE 
      WHEN COUNT(CASE WHEN di.seq_num = 1 
                      AND ((di.icd_version = 9 AND di.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '436'))
                           OR (di.icd_version = 10 AND di.icd_code LIKE 'I63%'))
                 THEN 1 END) > 0 
      THEN 'Primary' 
      ELSE 'Secondary' 
    END AS stroke_type
  FROM stroke_hadms sh
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON sh.subject_id = di.subject_id AND sh.hadm_id = di.hadm_id
  GROUP BY sh.subject_id, sh.hadm_id
),
admissions_with_stroke AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    sc.stroke_type,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN stroke_classification sc 
    ON a.subject_id = sc.subject_id AND a.hadm_id = sc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 49 AND 59
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 8
)
SELECT 
  aws.los_group,
  aws.stroke_type,
  AVG(COALESCE(proc.num_procedures, 0)) AS mean_procedures,
  MIN(COALESCE(proc.num_procedures, 0)) AS min_procedures,
  MAX(COALESCE(proc.num_procedures, 0)) AS max_procedures
FROM admissions_with_stroke aws
LEFT JOIN (
  SELECT hadm_id, COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
) proc ON aws.hadm_id = proc.hadm_id
GROUP BY aws.los_group, aws.stroke_type
ORDER BY aws.los_group, aws.stroke_type;