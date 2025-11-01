WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.dischtime,
    adm.admittime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate LOS in days (handles fractional days)
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Define outcome groups
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'DEATH'
      WHEN adm.discharge_location = 'HOME' THEN 'HOME'
      WHEN adm.discharge_location LIKE 'Hospice%' THEN 'HOSPICE'
    END AS outcome_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND adm.admission_location = 'Transfer from another hospital'
    -- Compute age at admission and filter
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year))
        BETWEEN 63 AND 73
)
SELECT
  outcome_group,
  COUNT(*) AS num_admissions,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days
FROM
  cohort
WHERE
  outcome_group IS NOT NULL  -- Only include the three defined groups
GROUP BY
  outcome_group
ORDER BY
  outcome_group;