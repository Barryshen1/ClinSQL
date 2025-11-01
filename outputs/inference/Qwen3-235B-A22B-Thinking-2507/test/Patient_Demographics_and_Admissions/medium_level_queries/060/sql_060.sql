WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    -- Calculate age at admission using MIMIC-IV de-identification rules
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit,
    -- Compute LOS in precise decimal days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    -- Categorize discharge outcomes per clinical question
    CASE
      WHEN adm.discharge_location = 'HOME' THEN 'home'
      WHEN LOWER(adm.discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN adm.discharge_location = 'DEAD/EXPIRED' THEN 'in-hospital death'
      ELSE NULL
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    adm.dischtime IS NOT NULL  -- Exclude ongoing admissions
    AND adm.admission_location = 'EMERGENCY ROOM ADMIT'
    AND pat.gender = 'F'
    -- Age filter: 50-60 inclusive at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 50 AND 60
)
SELECT
  outcome,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  (COUNTIF(los_days <= 10) * 100.0) / COUNT(*) AS percent_los_le_10
FROM filtered_admissions
WHERE outcome IS NOT NULL  -- Keep only the three specified outcomes
GROUP BY outcome
ORDER BY outcome;