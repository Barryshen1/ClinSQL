WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),
first_admissions AS (
  SELECT a.subject_id, MIN(a.admittime) AS first_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  GROUP BY a.subject_id
)
SELECT STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN first_admissions fa ON a.subject_id = fa.subject_id
  AND a.admittime = fa.first_admittime
WHERE a.dischtime IS NOT NULL;