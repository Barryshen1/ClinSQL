WITH stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    p.gender,
    p.anchor_age,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (subject_id, hadm_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND icu.los IS NOT NULL
),

labeled AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS outcome
  FROM stays
)

SELECT
  outcome,
  COUNT(*) AS n_stays,
  -- approximate quantiles (array index corresponds to percentile); SAFE_OFFSET used for safety
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(50)] AS p50_days,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(75)] AS p75_days,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(90)] AS p90_days,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(95)] AS p95_days,
  100.0 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*) AS pct_le_7_days
FROM labeled
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY
  CASE outcome
    WHEN 'home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'in-hospital death' THEN 3
    ELSE 4
  END;