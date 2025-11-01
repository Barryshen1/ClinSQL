SELECT
  discharge_group,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS stddev_los,
  AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100 AS pct_le_10_days
FROM (
  SELECT
    subject_id,
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE NULL
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IS NOT NULL
    AND admittime IS NOT NULL
    AND dischtime IS NOT NULL
    AND admission_location = 'EMERGENCY ROOM'
    AND discharge_location IS NOT NULL
) AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON
  adm.subject_id = pat.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 50 AND 60
  AND adm.discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;