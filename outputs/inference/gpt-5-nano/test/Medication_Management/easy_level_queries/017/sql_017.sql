SELECT
  AVG(duration_days) AS avg_warfarin_duration_days
FROM (
  SELECT
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = a.subject_id
   AND pr.hadm_id = a.hadm_id
  WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 43 AND 53
      -- inpatient admission context
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
      -- warfarin identification (case-insensitive)
      AND LOWER(pr.drug) LIKE '%warfarin%'
      -- data quality for durations
      AND pr.starttime IS NOT NULL
      AND pr.stoptime IS NOT NULL
      AND pr.stoptime >= pr.starttime
) t;