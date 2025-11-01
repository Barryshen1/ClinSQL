SELECT
  death_loc_category,
  COUNT(*)                                AS n_icustays,
  ROUND(AVG(los), 2)                      AS mean_los_days,
  ROUND(STDDEV_POP(los), 2)               AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                          AS pct_los_lt_10_days
FROM (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag,
    adm.discharge_location,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN adm.discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS death_loc_category
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND icu.los IS NOT NULL
)
GROUP BY
  death_loc_category
ORDER BY
  death_loc_category;