WITH patient_stays AS (
  SELECT
    icu.stay_id,
    icu.los,
    -- Compute age at hospital admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age,
    -- Define discharge outcome groups
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN adm.discharge_location LIKE 'HOSPICE%' THEN 'hospice'
      WHEN adm.discharge_location = 'HOME' THEN 'home'
      ELSE 'other'
    END AS outcome_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id AND icu.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
)

SELECT
  outcome_group,
  -- LOS percentiles
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  -- % of stays with LOS <= 7 days
  COUNT(*) AS total_stays,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) AS stays_leq_7,
  ROUND(100 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_leq_7
FROM patient_stays
WHERE
  age BETWEEN 40 AND 50
  AND outcome_group IN ('in-hospital death', 'hospice', 'home')  -- Exclude 'other'
GROUP BY outcome_group
ORDER BY outcome_group;