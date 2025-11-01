WITH ami_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age,
    a.admittime, a.dischtime, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),
risk_scores AS (
  SELECT c.subject_id, c.hadm_id, AVG(ce.valuenum) AS avg_risk_percentile
  FROM ami_cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%risk%percentile%'
  GROUP BY c.subject_id, c.hadm_id
),
aki_flags AS (
  SELECT DISTINCT a.hadm_id, 1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN ami_cohort a
    ON di.hadm_id = a.hadm_id
  WHERE LOWER(dd.long_title) LIKE '%acute kidney injury%'
    OR LOWER(dd.long_title) LIKE '%acute renal failure%'
),
ards_flags AS (
  SELECT DISTINCT a.hadm_id, 1 AS ards_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN ami_cohort a
    ON di.hadm_id = a.hadm_id
  WHERE LOWER(dd.long_title) LIKE '%acute respiratory distress%'
     OR LOWER(dd.long_title) LIKE '%ards%'
),
cohort_outcomes AS (
  SELECT c.subject_id, c.hadm_id,
    rs.avg_risk_percentile,
    CASE
      WHEN c.dod IS NOT NULL AND DATETIME_DIFF(c.dod, c.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    IFNULL(ak.aki_flag, 0) AS aki_flag,
    IFNULL(ar.ards_flag, 0) AS ards_flag,
    CASE
      WHEN c.dod IS NOT NULL THEN DATETIME_DIFF(c.dod, c.admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM ami_cohort c
  LEFT JOIN risk_scores rs
    ON c.subject_id = rs.subject_id AND c.hadm_id = rs.hadm_id
  LEFT JOIN aki_flags ak
    ON c.hadm_id = ak.hadm_id
  LEFT JOIN ards_flags ar
    ON c.hadm_id = ar.hadm_id
)
SELECT
  AVG(avg_risk_percentile) AS mean_composite_risk_percentile,
  AVG(mortality_30d) AS cohort_30d_mortality_rate,
  AVG(aki_flag) AS aki_rate,
  AVG(ards_flag) AS ards_rate,
  APPROX_QUANTILES(survival_days, 100)[SAFE_OFFSET(50)] AS median_survival_days_decedents
FROM cohort_outcomes
WHERE TRUE
  -- To calculate median survival only among decedents, we'll apply filter inside quantiles;