WITH pe_cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      dd.icd_code LIKE '415.1%'  -- ICD-9: pulmonary embolism
      OR dd.icd_code LIKE 'I26%' -- ICD-10: pulmonary embolism
      OR LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    )
),

-- Select first ICU stay per admission to avoid duplicates
first_icu_stay AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM pe_cohort
),

pe_cohort_first AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),

diagnostic_scores AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT ce.itemid) + COUNT(DISTINCT le.itemid) AS diagnostic_count
  FROM pe_cohort_first p
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON p.stay_id = ce.stay_id
    AND ce.charttime >= p.intime
    AND ce.charttime < TIMESTAMP_ADD(p.intime, INTERVAL 24 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON p.hadm_id = le.hadm_id
    AND le.charttime >= p.intime
    AND le.charttime < TIMESTAMP_ADD(p.intime, INTERVAL 24 HOUR)
  GROUP BY p.stay_id
),

cohort_metrics AS (
  SELECT
    PERCENTILE_CONT(diagnostic_count, 0.75) AS pct75_diagnostic_score,
    MEDIAN(los) AS cohort_los,
    AVG(hospital_expire_flag) AS cohort_mortality_rate
  FROM pe_cohort_first p
  LEFT JOIN diagnostic_scores ds ON p.stay_id = ds.stay_id
),

general_metrics AS (
  SELECT
    MEDIAN(los) AS general_los,
    AVG(a.hospital_expire_flag) AS general_mortality_rate
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
)

SELECT
  cm.pct75_diagnostic_score,
  cm.cohort_los,
  cm.cohort_mortality_rate,
  gm.general_los,
  gm.general_mortality_rate
FROM cohort_metrics cm
CROSS JOIN general_metrics gm;