WITH med_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(a.discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  -- restrict to men aged 74–84
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    -- later filter to discharge categories of interest
    -- but we can do that after joining services
),
med_inpatient_adms AS (
  -- restrict to admissions that ever had a MEDICINE service
  SELECT DISTINCT
    m.subject_id,
    m.hadm_id,
    m.los,
    m.discharge_category
  FROM
    med_admissions m
  JOIN
    `physionet-data.mimiciv_3_1_hosp.services` s
  ON
    m.hadm_id = s.hadm_id
  WHERE
    UPPER(s.curr_service) = 'MEDICINE'
    AND m.discharge_category IS NOT NULL
)
SELECT
  discharge_category,
  COUNT(*)                 AS n,
  ROUND(AVG(los), 2)       AS mean_los,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END),
      COUNT(*)
    ), 4
  )                        AS prop_los_le_5
FROM
  med_inpatient_adms
GROUP BY
  discharge_category
ORDER BY
  discharge_category;