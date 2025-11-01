WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    adm.discharge_location,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admit,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  WHERE
    pt.gender = 'F'
    AND adm.admission_type = 'EMERGENCY'
    -- Filter age at admission (77-87)
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 77 AND 87
    -- Include only relevant outcomes
    AND adm.discharge_location IN ('HOME', 'HOSPICE', 'DEAD/EXPIRED')
)

SELECT
  CASE
    WHEN discharge_location = 'HOME' THEN 'Discharged Home'
    WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
    WHEN discharge_location = 'DEAD/EXPIRED' THEN 'In-Hospital Death'
  END AS outcome_group,
  -- Calculate median and IQR
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr_los_days
FROM
  filtered_admissions
GROUP BY
  outcome_group
ORDER BY
  outcome_group;