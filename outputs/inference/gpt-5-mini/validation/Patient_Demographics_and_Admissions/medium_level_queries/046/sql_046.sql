SELECT
  grp AS group_label,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los), 2) AS sd_los_days,
  CONCAT(
    CAST(ROUND(AVG(los), 2) AS STRING),
    ' ± ',
    CAST(ROUND(STDDEV_SAMP(los), 2) AS STRING)
  ) AS mean_plus_minus_sd_days,
  ROUND(
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END), COUNT(*)),
    1
  ) AS pct_los_lt_10
FROM (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    p.anchor_age,
    COALESCE(LOWER(a.discharge_location), '') AS discharge_location_lower,
    a.hospital_expire_flag,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN (
           LOWER(COALESCE(a.discharge_location, '')) LIKE '%nurs%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%snf%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%skilled%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%rehab%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%facility%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%ltach%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%long term%'
        OR LOWER(COALESCE(a.discharge_location, '')) LIKE '%assisted%'
      ) THEN 'facility'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE 'other'
    END AS grp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND i.los IS NOT NULL
    AND i.los >= 0
) AS sub
WHERE grp IN ('home', 'facility', 'in-hospital death')
GROUP BY grp
ORDER BY
  CASE grp
    WHEN 'home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'in-hospital death' THEN 3
    ELSE 4
  END;