WITH cardiac_arrest_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(did.long_title) LIKE '%cardiac arrest%'
),

sofa_scores AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    MIN(c.valuenum) AS first_sofa_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE c.itemid = 228287  -- SOFA score
    AND c.charttime >= i.intime
    AND c.charttime <= i.intime + INTERVAL '24 hour'
    AND c.valuenum IS NOT NULL
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
),

cohort_with_risk AS (
  SELECT
    ca.*,
    s.first_sofa_score,
    CASE
      WHEN ca.deathtime IS NOT NULL AND ca.deathtime <= ca.admittime + INTERVAL '30 day' THEN 1
      WHEN ca.dod IS NOT NULL AND CAST(ca.dod AS TIMESTAMP) <= ca.admittime + INTERVAL '30 day' THEN 1
      ELSE 0
    END AS thirty_day_mortality
  FROM cardiac_arrest_cohort ca
  INNER JOIN sofa_scores s
    ON ca.subject_id = s.subject_id AND ca.hadm_id = s.hadm_id
),

complications AS (
  SELECT
    d.hadm_id,
    MAX(CASE
      WHEN LOWER(did.long_title) LIKE '%myocardial infarction%'
        OR LOWER(did.long_title) LIKE '%heart failure%'
        OR LOWER(did.long_title) LIKE '%cardiogenic shock%'
        OR LOWER(did.long_title) LIKE '%ventricular fibrillation%'
        OR LOWER(did.long_title) LIKE '%ventricular tachycardia%'
        OR LOWER(did.long_title) LIKE '%arrhythmia%'
        OR LOWER(did.long_title) LIKE '%cardiac arrest%'
      THEN 1 ELSE 0 END) AS cardiovascular_complication,
    MAX(CASE
      WHEN LOWER(did.long_title) LIKE '%stroke%'
        OR LOWER(did.long_title) LIKE '%cerebral infarction%'
        OR LOWER(did.long_title) LIKE '%intracerebral hemorrhage%'
        OR LOWER(did.long_title) LIKE '%subarachnoid hemorrhage%'
        OR LOWER(did.long_title) LIKE '%seizure%'
        OR LOWER(did.long_title) LIKE '%coma%'
        OR LOWER(did.long_title) LIKE '%neurologic deficit%'
      THEN 1 ELSE 0 END) AS neurologic_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE d.hadm_id IN (SELECT hadm_id FROM cohort_with_risk)
  GROUP BY d.hadm_id
),

final_cohort AS (
  SELECT
    c.*,
    COALESCE(comp.cardiovascular_complication, 0) AS cardiovascular_complication,
    COALESCE(comp.neurologic_complication, 0) AS neurologic_complication,
    NTILE(4) OVER (ORDER BY c.first_sofa_score) AS risk_quartile,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort_with_risk c
  LEFT JOIN complications comp ON c.hadm_id = comp.hadm_id
  WHERE c.first_sofa_score IS NOT NULL
)

SELECT
  risk_quartile,
  AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(cardiovascular_complication) AS cardiovascular_complication_rate,
  AVG(neurologic_complication) AS neurologic_complication_rate,
  PERCENTILE_CONT(CASE WHEN thirty_day_mortality = 0 THEN los_days END, 0.5) AS median_survivor_los_days,
  (SELECT AVG(thirty_day_mortality) FROM final_cohort) AS baseline_thirty_day_mortality
FROM final_cohort
GROUP BY risk_quartile
ORDER BY risk_quartile;