WITH eligible_admissions AS (
  SELECT
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location IN ('EMERGENCY ROOM', 'EMERGENCY')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE 
    WHEN hospital_expire_flag = 0 THEN 'Alive'
    WHEN hospital_expire_flag = 1 THEN 'Died'
  END AS discharge_status,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_los_ge7,
  SUM(CASE WHEN los >= 14 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_los_ge14
FROM
  eligible_admissions
GROUP BY
  hospital_expire_flag

UNION ALL

SELECT
  'Overall: Percentile Rank for 10-day LOS' AS discharge_status,
  NULL AS prop_los_ge7,
  (SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) AS prop_los_ge14
FROM
  eligible_admissions
ORDER BY
  discharge_status;