WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    -- Compute age at admission (approximation)
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    -- Calculate LOS in whole days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Categorize discharge outcome
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      ELSE 'facility'
    END AS outcome_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND adm.admission_type IN ('EMERGENCY', 'URGENT')
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    -- Filter age range (37-47 inclusive)
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 37 AND 47
)
SELECT
  outcome_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25,  -- 25th percentile
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50,  -- 50th percentile (median)
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75,  -- 75th percentile
  (COUNTIF(los_days <= 7) * 100.0 / COUNT(*)) AS percentile_rank_7  -- % of stays ≤7 days
FROM filtered_admissions
GROUP BY outcome_category
ORDER BY outcome_category;