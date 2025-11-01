WITH filtered AS (
  SELECT
    adm.hadm_id,
    pat.subject_id,
    pat.gender,
    pat.anchor_age,
    adm.admission_type,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      ELSE 'Other'
    END AS disposition_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND adm.admission_type = 'EMERGENCY'
)
SELECT
  disposition_group,
  quantiles[OFFSET(2)] AS median_los_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_los_days
FROM (
  SELECT
    disposition_group,
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM filtered
  WHERE disposition_group IN ('Home', 'Hospice', 'In-hospital death')
  GROUP BY disposition_group
)
ORDER BY disposition_group;