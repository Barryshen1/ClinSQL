WITH icu_female_40_50 AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los, -- LOS in days
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(a.discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE NULL
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id 
   AND i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 40 AND 50
    AND (
      a.hospital_expire_flag = 1
      OR UPPER(a.discharge_location) LIKE '%HOSPICE%'
      OR UPPER(a.discharge_location) LIKE '%HOME%'
    )
)

SELECT
  outcome,
  COUNT(*) AS n_icustays,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS p50_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)], 2) AS p75_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)], 2) AS p90_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(95)], 2) AS p95_los,
  ROUND(100 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_le_7d
FROM icu_female_40_50
GROUP BY outcome
ORDER BY outcome;