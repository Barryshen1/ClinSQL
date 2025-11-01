WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age AS age_adm,
    -- Compute LOS in fractional days
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Define outcome groups
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(adm.discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
    END AS outcome_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND adm.admission_location = 'EMERGENCY ROOM'
    -- Ensure valid LOS and age
    AND adm.dischtime > adm.admittime
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 50 AND 60
)

SELECT
  outcome_group,
  COUNT(*) AS total_patients,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  (COUNTIF(los_days <= 10) / COUNT(*)) * 100 AS pct_los_leq_10_days
FROM
  cohort
WHERE
  outcome_group IS NOT NULL  -- Include only the 3 specified outcomes
GROUP BY
  outcome_group;