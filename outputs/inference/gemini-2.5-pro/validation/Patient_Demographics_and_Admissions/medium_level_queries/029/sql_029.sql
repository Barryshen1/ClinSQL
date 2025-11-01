WITH admission_icu_los AS (
  -- First, identify all hospital admissions for female patients aged 35-45.
  -- Then, for each admission, calculate the total ICU length of stay by summing
  -- the LOS from all associated ICU stays.
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    SUM(icu.los) AS total_icu_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    -- This INNER JOIN ensures we only consider hospital admissions that had an ICU stay
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 35 AND 45
  GROUP BY
    adm.hadm_id,
    adm.hospital_expire_flag
)
-- Finally, aggregate the results by survival status to compute the required metrics.
SELECT
  CASE
    WHEN hospital_expire_flag = 0
      THEN 'Discharged Alive'
    ELSE 'In-Hospital Death'
  END AS survival_status,
  COUNT(hadm_id) AS number_of_admissions,
  AVG(total_icu_los_days) AS mean_los_days,
  STDDEV(total_icu_los_days) AS stddev_los_days,
  SAFE_DIVIDE(COUNTIF(total_icu_los_days < 7), COUNT(hadm_id)) * 100 AS percent_los_less_than_7_days
FROM
  admission_icu_los
GROUP BY
  survival_status
ORDER BY
  survival_status;