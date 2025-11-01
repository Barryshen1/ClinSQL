WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'HOME'
      WHEN a.discharge_location = 'HOSPICE' THEN 'HOSPICE'
      WHEN a.hospital_expire_flag = 1 THEN 'DIED'
    END AS disch_stratum
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.services s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND s.curr_service = 'MED'
    AND a.discharge_location IN ('HOME', 'HOSPICE')
    OR a.hospital_expire_flag = 1
),
stratum_stats AS (
  SELECT
    disch_stratum,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
    AVG(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) AS prop_los_le_5
  FROM
    cohort
  WHERE
    disch_stratum IS NOT NULL
  GROUP BY
    disch_stratum
)
SELECT
  disch_stratum,
  mean_los,
  median_los,
  prop_los_le_5
FROM
  stratum_stats
ORDER BY
  disch_stratum;