WITH base_acs AS (
  -- Female patients aged 67-77 at admission with ACS diagnosis
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age IS NOT NULL)
    AND (p.anchor_year IS NOT NULL)
    AND ((p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77)
    AND (
      dd.long_title LIKE '%acute coronary%' OR
      dd.long_title LIKE '%unstable angina%' OR
      dd.long_title LIKE '%myocardial infarction%' OR
      dd.long_title LIKE '%acute coronary syndrome%'
    )
),
initial_troponin AS (
  -- Initial Troponin T per admission
  SELECT le.hadm_id, le.subject_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponin t%'
    AND le.hadm_id IN (SELECT hadm_id FROM base_acs)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
threshold AS (
  -- 99th percentile of initial Troponin T values
  SELECT quantiles[OFFSET(99)] AS thresh
  FROM (
    SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles
    FROM initial_troponin
  )
),
final_cohort AS (
  -- Admissions with initial Troponin T above 99th percentile
  SELECT i.hadm_id, i.subject_id, i.charttime, i.valuenum
  FROM initial_troponin i
  CROSS JOIN threshold t
  WHERE i.valuenum > t.thresh
)

SELECT
  (SELECT COUNT(DISTINCT subject_id) FROM final_cohort) AS num_patients,
  (SELECT COUNT(DISTINCT hadm_id) FROM final_cohort) AS num_admissions,
  (SELECT AVG(valuenum) FROM final_cohort) AS mean_troponin,
  (SELECT quantiles[OFFSET(50)]
     FROM (SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles FROM final_cohort)
  ) AS median_troponin,
  (SELECT (quantiles[OFFSET(75)] - quantiles[OFFSET(25)])
     FROM (SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles FROM final_cohort)
  ) AS iqr_troponin;