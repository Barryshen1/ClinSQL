WITH
  -- Population: male, age 68-78, ICU involvement, ICH via ICD long_title
  ich_cohort AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON ic.hadm_id = a.hadm_id AND ic.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 68 AND 78
      AND REGEXP_CONTAINS(LOWER(dd.long_title), r'intracranial.*hemorrhage')
  ),

  -- AKI present per admission
  aki_present AS (
    SELECT di.hadm_id, 1 AS aki_present
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.hadm_id IN (SELECT hadm_id FROM ich_cohort)
      AND REGEXP_CONTAINS(LOWER(dd.long_title),
                          r'(acute kidney|acute kidney injury|kidney injury)')
  ),

  -- ARDS present per admission
  ards_present AS (
    SELECT di.hadm_id, 1 AS ards_present
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.hadm_id IN (SELECT hadm_id FROM ich_cohort)
      AND REGEXP_CONTAINS(LOWER(dd.long_title),
                          r'acute\s+respiratory\s+distress\s+syndrome')
  ),

  -- 30-day mortality indicator per admission (rename to avoid conflict)
  death30_cte AS (
    SELECT ic.hadm_id,
           CASE
             WHEN a.deathtime IS NOT NULL
                  AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30
             THEN 1 ELSE 0
           END AS death30
    FROM ich_cohort ic
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON a.hadm_id = ic.hadm_id
  ),

  -- Composite score: AKI_present + ARDS_present
  score_table AS (
    SELECT ic.hadm_id,
           COALESCE(ak.aki_present, 0) + COALESCE(ar.ards_present, 0) AS score
    FROM ich_cohort ic
    LEFT JOIN aki_present ak  ON ic.hadm_id = ak.hadm_id
    LEFT JOIN ards_present ar ON ic.hadm_id = ar.hadm_id
  ),

  -- 25th/50th/75th percentiles for the composite score
  score_quantiles AS (
    SELECT quantiles[OFFSET(1)] AS p25,
           quantiles[OFFSET(2)] AS p50,
           quantiles[OFFSET(3)] AS p75
    FROM (
      SELECT APPROX_QUANTILES(score, 4) AS quantiles
      FROM score_table
    )
  ),

  -- Median survival days among decedents
  deceased_days AS (
    SELECT TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) AS days_to_death
    FROM ich_cohort ic
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON a.hadm_id = ic.hadm_id
    WHERE a.deathtime IS NOT NULL
  ),
  median_survival AS (
    SELECT APPROX_QUANTILES(days_to_death, 100)[OFFSET(50)] AS median_days
    FROM deceased_days
  )

SELECT
  (SELECT COUNT(*) FROM ich_cohort) AS cohort_size,
  (SELECT SUM(death30) FROM death30_cte) AS deaths_30d,
  (SELECT AVG(score) FROM score_table) AS mean_composite,
  (SELECT p25 FROM score_quantiles) AS p25,
  (SELECT p50 FROM score_quantiles) AS p50,
  (SELECT p75 FROM score_quantiles) AS p75,
  (SELECT median_days FROM median_survival) AS median_survival_days
FROM (SELECT 1) AS dummy;