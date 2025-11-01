WITH discharge_data AS (
  SELECT
    i.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.discharge_location IS NOT NULL
)
SELECT
  discharge_outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.5) AS median_los,
  AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0.0 END) * 100 AS percent_le_10
FROM
  discharge_data
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;