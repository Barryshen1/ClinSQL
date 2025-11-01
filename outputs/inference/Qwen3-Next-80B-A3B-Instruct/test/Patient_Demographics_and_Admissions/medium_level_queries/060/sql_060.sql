WITH discharge_outcomes AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days,
    -- Classify discharge outcome
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE NULL
    END AS discharge_outcome
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.discharge_location IS NOT NULL
)
SELECT
  discharge_outcome,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  (SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_le_10_days
FROM
  discharge_outcomes
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;