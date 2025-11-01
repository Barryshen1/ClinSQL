WITH filtered_icu_stays AS (
  SELECT
    i.los,
    a.hospital_expire_flag,
    a.discharge_location
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
    AND i.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND i.los IS NOT NULL
),
categorized_outcomes AS (
  SELECT
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN discharge_location LIKE '%HOME%' OR discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME WITH HOME HEALTH CARE') THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM
    filtered_icu_stays
)
SELECT
  discharge_outcome,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los,
  AVG(CASE WHEN los <= 7 THEN 1.0 ELSE 0.0 END) * 100 AS pct_le_7_days
FROM
  categorized_outcomes
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;