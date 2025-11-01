WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admission_location,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATETIME_DIFF(
      COALESCE(adm.dischtime, adm.deathtime),
      adm.admittime,
      DAY
    ) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND UPPER(adm.admission_location) LIKE 'EMER%'
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN UPPER(discharge_location) LIKE 'HOSPICE%' THEN 'Hospice'
    WHEN UPPER(discharge_location) LIKE 'HOME%' THEN 'Home'
    ELSE 'Other'
  END AS discharge_outcome,
  COUNT(*) AS n_admissions,
  AVG(los) AS mean_los_days,
  STDDEV(los) AS sd_los_days,
  100 * COUNTIF(los <= 10) / COUNT(*) AS pct_los_le_10_days
FROM
  cohort
WHERE
  -- only keep the three categories of interest
  (hospital_expire_flag = 1
    OR UPPER(discharge_location) LIKE 'HOSPICE%'
    OR UPPER(discharge_location) LIKE 'HOME%')
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;