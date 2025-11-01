SELECT
  hospital_expire_flag AS discharge_status,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(STDDEV(los), 2) AS std_los,
  ROUND(AVG(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 100, 2) AS percent_los_le7
FROM (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    DATEDIFF(a.dischtime, a.admittime) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'ED'
)
GROUP BY
  hospital_expire_flag
ORDER BY
  discharge_status;