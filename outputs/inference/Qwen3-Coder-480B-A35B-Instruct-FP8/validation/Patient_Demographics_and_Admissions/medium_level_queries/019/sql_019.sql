WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Died in Hospital'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'Discharged to Hospice'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'Discharged Home'
      ELSE 'Other'
    END AS discharge_group
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_location LIKE '%HOSPITAL%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
)

SELECT
  discharge_group,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS stddev_los
FROM
  cohort
WHERE
  discharge_group IN ('Discharged Home', 'Discharged to Hospice', 'Died in Hospital')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;