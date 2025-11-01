SELECT
  death_group,
  COUNT(*) AS n,
  AVG(icu_los) AS mean_los_days,
  STDDEV_SAMP(icu_los) AS sd_los_days,
  100.0 * SUM(CASE WHEN icu_los < 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_lt_10
FROM (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.los AS icu_los,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(adm.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(adm.discharge_location) LIKE '%facility%'
           OR LOWER(adm.discharge_location) LIKE '%snf%'
           OR LOWER(adm.discharge_location) LIKE '%rehab%'
      THEN 'Facility'
      ELSE NULL
    END AS death_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE UPPER(pat.gender) = 'FEMALE'
    AND pat.anchor_age BETWEEN 87 AND 97
    AND icu.los IS NOT NULL
) AS t
WHERE death_group IS NOT NULL
GROUP BY death_group
ORDER BY death_group;