WITH base AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    adm.discharge_location,
    -- Calculate age at admission using MIMIC-IV standard method
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm,
    -- Compute LOS in integer days (admittime to dischtime)
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_location LIKE '%EMERGENCY%'
    -- Filter age 41-51 inclusive
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 41 AND 51
    -- Ensure valid discharge time for LOS calculation
    AND adm.dischtime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    WHEN discharge_location = 'HOME' THEN 'home'
    ELSE 'facility'
  END AS discharge_category,
  -- Proportion with LOS ≥ 7 days
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS proportion_los_ge7,
  -- Percentile rank for 10-day LOS: % of patients with LOS ≤ 10
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_10
FROM base
GROUP BY discharge_category
ORDER BY discharge_category;