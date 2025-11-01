WITH female_44_54 AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

ich_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
   AND dx.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%subarachnoid hemorrhage%'
),

drg AS (
  SELECT hadm_id, 
         SAFE_CAST(drg_severity AS INT64) AS drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
),

complication_flags AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
   AND dx.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
     OR LOWER(dd.long_title) LIKE '%acute kidney failure%'
     OR LOWER(dd.long_title) LIKE '%respiratory failure%'
),

cohort_a AS (
  SELECT f.*, drg.drg_severity,
         DATE_DIFF(f.dod, f.admittime, DAY) AS days_to_death,
         TIMESTAMP_DIFF(f.dischtime, f.admittime, DAY) AS los,
         IF(cf.hadm_id IS NOT NULL, 1, 0) AS major_complication
  FROM female_44_54 f
  JOIN ich_dx ich
    ON f.hadm_id = ich.hadm_id
  LEFT JOIN drg
    ON f.hadm_id = drg.hadm_id
  LEFT JOIN complication_flags cf
    ON f.hadm_id = cf.hadm_id
),

cohort_b AS (
  SELECT f.*, drg.drg_severity,
         DATE_DIFF(f.dod, f.admittime, DAY) AS days_to_death,
         TIMESTAMP_DIFF(f.dischtime, f.admittime, DAY) AS los,
         IF(cf.hadm_id IS NOT NULL, 1, 0) AS major_complication
  FROM female_44_54 f
  LEFT JOIN drg
    ON f.hadm_id = drg.hadm_id
  LEFT JOIN complication_flags cf
    ON f.hadm_id = cf.hadm_id
)

SELECT
  -- Cohort A: median/IQR DRG severity
  (SELECT ROUND(APPROX_QUANTILES(drg_severity, 4)[OFFSET(2)], 1) 
     FROM cohort_a WHERE drg_severity IS NOT NULL) AS cohortA_median_risk,
  (SELECT CONCAT(
            ROUND(APPROX_QUANTILES(drg_severity, 4)[OFFSET(1)], 1),
            ' - ',
            ROUND(APPROX_QUANTILES(drg_severity, 4)[OFFSET(3)], 1))
     FROM cohort_a WHERE drg_severity IS NOT NULL) AS cohortA_IQR_risk,

  -- Cohort A: 90-day mortality
  (SELECT ROUND(100 * SUM(CASE WHEN days_to_death IS NOT NULL AND days_to_death <= 90 THEN 1 ELSE 0 END)/COUNT(*), 1)
     FROM cohort_a) AS cohortA_90d_mortality_pct,

  -- Major complication rate comparison
  (SELECT ROUND(100 * SUM(major_complication)/COUNT(*), 1) FROM cohort_a) AS cohortA_major_complication_pct,
  (SELECT ROUND(100 * SUM(major_complication)/COUNT(*), 1) FROM cohort_b) AS cohortB_major_complication_pct,

  -- Median survivor LOS
  (SELECT ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 1) 
     FROM cohort_a WHERE days_to_death IS NULL OR days_to_death > 90) AS cohortA_median_survivor_LOS_days,
  (SELECT ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 1) 
     FROM cohort_b WHERE days_to_death IS NULL OR days_to_death > 90) AS cohortB_median_survivor_LOS_days,

  -- Matched risk percentile for a specific patient (example: subject_id X hadm_id Y)
  (SELECT ROUND(100 * PERCENT_RANK() OVER (ORDER BY drg_severity), 1)
     FROM cohort_b
     WHERE subject_id = 123456 AND hadm_id = 789012) AS patient_risk_percentile;