WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Age/sex filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    -- LOS >= 96h
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),
dx AS (
  SELECT di.subject_id, di.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.subject_id, di.hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  WHERE d.has_diabetes = 1 AND d.has_hf = 1
),
presc AS (
  SELECT pr.subject_id, pr.hadm_id, pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' AND (
           LOWER(pr.drug) LIKE '%glargine%' OR
           LOWER(pr.drug) LIKE '%detemir%' OR
           LOWER(pr.drug) LIKE '%degludec%' OR
           LOWER(pr.drug) LIKE '%nph%'
         ) THEN 'basal'
      WHEN LOWER(pr.drug) LIKE '%insulin%' AND (
           LOWER(pr.drug) LIKE '%lispro%' OR
           LOWER(pr.drug) LIKE '%aspart%' OR
           LOWER(pr.drug) LIKE '%glulisine%' OR
           LOWER(pr.drug) LIKE '%regular%'
         ) THEN 'bolus'
      WHEN LOWER(pr.drug) LIKE '%sliding%' THEN 'sliding_scale'
      ELSE NULL
    END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE LOWER(pr.drug) LIKE '%insulin%'
),
presc_cohort AS (
  SELECT p.*, adm.admittime, adm.dischtime
  FROM presc p
  JOIN cohort_with_dx adm
    ON p.subject_id = adm.subject_id AND p.hadm_id = adm.hadm_id
  WHERE insulin_type IS NOT NULL
),
time_window_flag AS (
  SELECT subject_id, hadm_id, insulin_type,
    CASE
      WHEN TIMESTAMP_DIFF(starttime, admittime, HOUR) BETWEEN 0 AND 48 THEN 'early'
      WHEN TIMESTAMP_DIFF(dischtime, starttime, HOUR) BETWEEN 0 AND 48 THEN 'final'
      ELSE NULL
    END AS time_window
  FROM presc_cohort
),
window_regimen AS (
  -- Determine regimen type per time_window per admission
  SELECT subject_id, hadm_id, time_window,
    CASE
      WHEN COUNTIF(insulin_type = 'basal') > 0 AND COUNTIF(insulin_type = 'bolus') > 0 THEN 'basal_bolus'
      WHEN COUNTIF(insulin_type = 'basal') > 0 THEN 'basal'
      WHEN COUNTIF(insulin_type = 'bolus') > 0 THEN 'bolus'
      WHEN COUNTIF(insulin_type = 'sliding_scale') > 0 THEN 'sliding_scale'
      ELSE NULL
    END AS regimen
  FROM time_window_flag
  WHERE time_window IS NOT NULL
  GROUP BY subject_id, hadm_id, time_window
),
early_final AS (
  SELECT e.subject_id, e.hadm_id,
         e.regimen AS early_regimen,
         f.regimen AS final_regimen
  FROM (SELECT * FROM window_regimen WHERE time_window = 'early') e
  FULL OUTER JOIN (SELECT * FROM window_regimen WHERE time_window = 'final') f
    ON e.subject_id = f.subject_id AND e.hadm_id = f.hadm_id
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_n
  FROM cohort_with_dx
)
-- Output 1: Percentages
SELECT 'percentages' AS section, time_window, regimen,
  COUNT(DISTINCT hadm_id) AS n,
  ROUND(100 * COUNT(DISTINCT hadm_id)/tc.total_n, 2) AS pct
FROM window_regimen, total_cohort tc
GROUP BY section, time_window, regimen, tc.total_n
UNION ALL
-- Output 2: Transitions
SELECT 'transitions' AS section,
  CONCAT(COALESCE(early_regimen,'none'), '->', COALESCE(final_regimen,'none')) AS time_window,
  NULL AS regimen,
  COUNT(*) AS n,
  ROUND(100 * COUNT(*)/tc.total_n, 2) AS pct
FROM early_final, total_cohort tc
GROUP BY section, time_window, tc.total_n
ORDER BY section, time_window;