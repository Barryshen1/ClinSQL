SELECT
  discharge_outcome,
  quantiles[OFFSET(50)] AS p50_los,
  quantiles[OFFSET(75)] AS p75_los,
  quantiles[OFFSET(90)] AS p90_los,
  quantiles[OFFSET(95)] AS p95_los,
  SAFE_DIVIDE(sum_le7, total) * 100.0 AS pct_le_7d,
  total AS n_stays
FROM (
  -- Aggregate per discharge outcome
  SELECT
    discharge_outcome,
    APPROX_QUANTILES(los, 100) AS quantiles,
    SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) AS sum_le7,
    COUNT(*) AS total
  FROM (
    -- Filter to female ICU stays, age 40–50, derive discharge outcome
    SELECT
      icu.los,
      CASE
        WHEN adm.hospital_expire_flag = 1 THEN 'in-hospital death'
        WHEN UPPER(adm.discharge_location) LIKE '%HOSPICE%' THEN 'hospice'
        WHEN UPPER(adm.discharge_location) LIKE 'HOME%' THEN 'home'
        ELSE NULL
      END AS discharge_outcome
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id = adm.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 40 AND 50
  ) sub
  WHERE discharge_outcome IS NOT NULL
  GROUP BY discharge_outcome
)
ORDER BY
  CASE discharge_outcome
    WHEN 'home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'in-hospital death' THEN 3
    ELSE 4
  END;