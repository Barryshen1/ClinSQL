WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, pat.anchor_age, pat.gender,
    a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  -- Female age 50-60
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
),
diabetes AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%diabetes%'
),
heart_failure AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart fail%'
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN diabetes dx ON c.hadm_id = dx.hadm_id
  JOIN heart_failure hf ON c.hadm_id = hf.hadm_id
),
glp1_initiations AS (
  SELECT p.hadm_id,
         MIN(p.starttime) AS first_glp1_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_with_dx cwd ON p.hadm_id = cwd.hadm_id
  WHERE LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%exenatide%'
     OR (LOWER(p.route) LIKE '%subcut%')
  GROUP BY p.hadm_id
),
classified AS (
  SELECT cwd.hadm_id,
         CASE
           WHEN first_glp1_time <= DATETIME_ADD(cwd.admittime, INTERVAL 72 HOUR)
             THEN 'first72h'
           WHEN first_glp1_time >= DATETIME_SUB(cwd.dischtime, INTERVAL 72 HOUR)
             THEN 'final72h'
           ELSE NULL
         END AS time_window
  FROM cohort_with_dx cwd
  LEFT JOIN glp1_initiations gi ON cwd.hadm_id = gi.hadm_id
)
SELECT
  COUNTIF(time_window = 'first72h') / COUNT(*) AS first72h_rate,
  COUNTIF(time_window = 'final72h') / COUNT(*) AS final72h_rate,
  (COUNTIF(time_window = 'final72h') / COUNT(*)) - (COUNTIF(time_window = 'first72h') / COUNT(*)) AS absolute_change,
  CASE WHEN COUNTIF(time_window = 'first72h') = 0 THEN NULL
       ELSE ((COUNTIF(time_window = 'final72h') / COUNT(*)) - (COUNTIF(time_window = 'first72h') / COUNT(*)))
              / (COUNTIF(time_window = 'first72h') / COUNT(*))
  END AS relative_change
FROM classified;