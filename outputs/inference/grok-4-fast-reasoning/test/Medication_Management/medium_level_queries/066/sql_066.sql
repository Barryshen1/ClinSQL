WITH patients_male_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 58 AND 68
),
admissions_long AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_male_age p ON a.subject_id = p.subject_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
cohort AS (
  SELECT al.subject_id, al.hadm_id, al.admittime, al.dischtime
  FROM admissions_long al
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.subject_id = al.subject_id
      AND d.hadm_id = al.hadm_id
      AND d.icd_version = 10
      AND d.icd_code LIKE 'E11%'
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    WHERE d2.subject_id = al.subject_id
      AND d2.hadm_id = al.hadm_id
      AND d2.icd_version = 10
      AND d2.icd_code LIKE 'I50%'
  )
),
total_n AS (
  SELECT COUNT(*) AS n_total
  FROM cohort
),
n_first_72h AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS n_first
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (
      LOWER(p.drug) LIKE '%liraglutide%' OR
      LOWER(p.drug) LIKE '%exenatide%' OR
      LOWER(p.drug) LIKE '%dulaglutide%' OR
      LOWER(p.drug) LIKE '%semaglutide%' OR
      LOWER(p.drug) LIKE '%lixisenatide%' OR
      LOWER(p.drug) LIKE '%albiglutide%' OR
      LOWER(p.drug) LIKE '%victoza%' OR
      LOWER(p.drug) LIKE '%byetta%' OR
      LOWER(p.drug) LIKE '%bydureon%' OR
      LOWER(p.drug) LIKE '%trulicity%' OR
      LOWER(p.drug) LIKE '%ozempic%' OR
      LOWER(p.drug) LIKE '%rybelsus%' OR
      LOWER(p.drug) LIKE '%adlyxin%' OR
      LOWER(p.drug) LIKE '%tanzeum%'
    )
),
n_final_12h AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS n_final
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND p.starttime < c.dischtime
    AND (
      LOWER(p.drug) LIKE '%liraglutide%' OR
      LOWER(p.drug) LIKE '%exenatide%' OR
      LOWER(p.drug) LIKE '%dulaglutide%' OR
      LOWER(p.drug) LIKE '%semaglutide%' OR
      LOWER(p.drug) LIKE '%lixisenatide%' OR
      LOWER(p.drug) LIKE '%albiglutide%' OR
      LOWER(p.drug) LIKE '%victoza%' OR
      LOWER(p.drug) LIKE '%byetta%' OR
      LOWER(p.drug) LIKE '%bydureon%' OR
      LOWER(p.drug) LIKE '%trulicity%' OR
      LOWER(p.drug) LIKE '%ozempic%' OR
      LOWER(p.drug) LIKE '%rybelsus%' OR
      LOWER(p.drug) LIKE '%adlyxin%' OR
      LOWER(p.drug) LIKE '%tanzeum%'
    )
)
SELECT
  ROUND((n_first / n_total * 100), 2) AS pct_first_72h,
  ROUND((n_final / n_total * 100), 2) AS pct_final_12h,
  ROUND(ABS((n_first / n_total * 100) - (n_final / n_total * 100)), 2) AS abs_diff_pp
FROM n_first_72h, n_final_12h, total_n;