WITH patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, p.anchor_year, p.gender, p.dod,
         a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) BETWEEN 59 AND 69
),

cardiac_arrest_admissions AS (
  SELECT DISTINCT p.hadm_id
  FROM patients_filtered p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON p.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'I46%'
),

cohort AS (
  SELECT p.*
  FROM patients_filtered p
  INNER JOIN cardiac_arrest_admissions ca
    ON p.hadm_id = ca.hadm_id
),

diagnosis_counts AS (
  SELECT hadm_id,
         COUNT(*) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY hadm_id
),

cv_neuro_diagnoses AS (
  SELECT hadm_id,
    MAX(CASE 
      WHEN SUBSTR(icd_code, 1, 3) IN ('I21','I22','I23','I24','I25','I44','I45','I47','I48','I49','I50') 
        OR (SUBSTR(icd_code, 1, 4) = 'I46.' AND icd_code != 'I46') 
      THEN 1 ELSE 0 END) AS has_cv_complication,
    MAX(CASE 
      WHEN SUBSTR(icd_code, 1, 3) IN ('I60','I61','I62','I63','I64','I65','I66','I67','I68','I69','G40','G41','G80','G81')
        OR icd_code = 'G93.4'
      THEN 1 ELSE 0 END) AS has_neuro_complication
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM cohort)
    AND d.icd_version = 10
  GROUP BY hadm_id
),

cohort_with_scores AS (
  SELECT c.*,
         dc.diagnosis_count,
         COALESCE(cv.has_cv_complication, 0) AS has_cv_complication,
         COALESCE(cv.has_neuro_complication, 0) AS has_neuro_complication,
         DATETIME_DIFF(c.dod, c.admittime, DAY) AS days_to_death,
         DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  LEFT JOIN diagnosis_counts dc ON c.hadm_id = dc.hadm_id
  LEFT JOIN cv_neuro_diagnoses cv ON c.hadm_id = cv.hadm_id
),

cohort_with_mortality AS (
  SELECT *,
    CASE 
      WHEN days_to_death IS NOT NULL AND days_to_death <= 30 THEN 1
      WHEN DATETIME_DIFF('2100-01-01', admittime, DAY) - DATETIME_DIFF('2100-01-01', dischtime, DAY) <= 30 
           AND hospital_expire_flag = 1 THEN 1
      ELSE 0 
    END AS died_within_30d
  FROM cohort_with_scores
),

quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY diagnosis_count) AS risk_quartile
  FROM cohort_with_mortality
),

quartile_stats AS (
  SELECT
    risk_quartile AS subgroup,
    AVG(CAST(died_within_30d AS FLOAT64)) AS mortality_rate,
    AVG(CAST(has_cv_complication AS FLOAT64)) AS cv_complication_rate,
    AVG(CAST(has_neuro_complication AS FLOAT64)) AS neuro_complication_rate,
    APPROX_QUANTILES(CASE WHEN died_within_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_survivor_los_days
  FROM quartiles
  GROUP BY risk_quartile
),

baseline_population AS (
  SELECT p.subject_id, p.dod, p.admittime, p.dischtime
  FROM patients_filtered p
),

baseline_stats AS (
  SELECT
    'baseline' AS subgroup,
    AVG(CAST(
      (dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) <= 30)
      AS FLOAT64)
    ) AS mortality_rate,
    CAST(NULL AS FLOAT64) AS cv_complication_rate,
    CAST(NULL AS FLOAT64) AS neuro_complication_rate,
    APPROX_QUANTILES(CASE 
      WHEN dod IS NULL OR DATETIME_DIFF(dod, admittime, DAY) > 30 
      THEN DATETIME_DIFF(dischtime, admittime, DAY) 
      END, 100)[OFFSET(50)] AS median_survivor_los_days
  FROM baseline_population
  WHERE admittime IS NOT NULL AND dischtime IS NOT NULL
)

SELECT
  CAST(subgroup AS STRING) AS subgroup,
  ROUND(mortality_rate, 4) AS mortality_rate,
  ROUND(cv_complication_rate, 4) AS cv_complication_rate,
  ROUND(neuro_complication_rate, 4) AS neuro_complication_rate,
  median_survivor_los_days
FROM quartile_stats

UNION ALL

SELECT
  subgroup,
  ROUND(mortality_rate, 4) AS mortality_rate,
  cv_complication_rate,
  neuro_complication_rate,
  median_survivor_los_days
FROM baseline_stats

ORDER BY subgroup;