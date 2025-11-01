WITH all_females_70_80 AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),

pe_cohort AS (
  SELECT 
    af.*
  FROM all_females_70_80 af
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE 
      diag.subject_id = af.subject_id
      AND diag.hadm_id = af.hadm_id
      AND (
        (diag.icd_version = 9 AND diag.icd_code LIKE '415.1%')
        OR 
        (diag.icd_version = 10 AND diag.icd_code LIKE 'I26%')
      )
  )
),

pe_with_quintile AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY age) AS quintile
  FROM pe_cohort
),

general_mortality AS (
  SELECT 
    COUNT(*) AS total,
    COUNTIF(dod <= DATETIME_ADD(admittime, INTERVAL 90 DAY)) AS deaths,
    COUNTIF(dod <= DATETIME_ADD(admittime, INTERVAL 90 DAY)) / COUNT(*) AS mortality_rate
  FROM all_females_70_80
),

aki_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%')
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
),

ards_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '518.82')
    OR (icd_version = 10 AND icd_code = 'J80')
)

SELECT 
  q.quintile,
  COUNT(q.subject_id) AS num_patients,
  COUNTIF(q.dod <= DATETIME_ADD(q.admittime, INTERVAL 90 DAY)) / COUNT(*) AS mortality_90d,
  (SELECT mortality_rate FROM general_mortality) AS general_mortality_90d,
  COUNTIF(aki.subject_id IS NOT NULL) / COUNT(*) AS aki_rate,
  COUNTIF(ards.subject_id IS NOT NULL) / COUNT(*) AS ards_rate,
  APPROX_QUANTILES(
    IF(q.hospital_expire_flag = 0, DATETIME_DIFF(q.dischtime, q.admittime, DAY), NULL), 
    100
  )[OFFSET(50)] AS median_survivor_los_days
FROM pe_with_quintile q
LEFT JOIN aki_patients aki
  ON q.subject_id = aki.subject_id AND q.hadm_id = aki.hadm_id
LEFT JOIN ards_patients ards
  ON q.subject_id = ards.subject_id AND q.hadm_id = ards.hadm_id
GROUP BY quintile
ORDER BY quintile;