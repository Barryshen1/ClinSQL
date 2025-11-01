WITH filtered_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    adm.discharge_location,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id    = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),
categorized AS (
  SELECT
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN UPPER(discharge_location) = 'HOME' THEN 'Home'
      ELSE NULL
    END AS outcome
  FROM
    filtered_stays
)
SELECT
  outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  -- median via approximate quantiles
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  100.0 * SUM(IF(los <= 10, 1, 0)) / COUNT(*) AS pct_le_10
FROM
  categorized
WHERE
  outcome IS NOT NULL
GROUP BY
  outcome
ORDER BY
  outcome;