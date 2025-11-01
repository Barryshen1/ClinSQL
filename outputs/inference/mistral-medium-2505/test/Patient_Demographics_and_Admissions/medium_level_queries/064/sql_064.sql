WITH female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),

icu_stays_with_discharge AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los AS icu_los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'DIED'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'HOME'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'HOSPICE'
      ELSE 'OTHER'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  JOIN
    female_patients p
  ON
    i.subject_id = p.subject_id
  WHERE
    a.discharge_location IS NOT NULL
)

SELECT
  discharge_outcome,
  COUNT(*) AS n,
  ROUND(AVG(icu_los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(icu_los, 100)[OFFSET(50)], 2) AS median_los,
  ROUND(100 * SUM(CASE WHEN icu_los <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_leq_10_days
FROM
  icu_stays_with_discharge
GROUP BY
  discharge_outcome
ORDER BY
  n DESC;