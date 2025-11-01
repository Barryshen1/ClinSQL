SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN a.discharge_location LIKE '%home%' THEN 'Home'
    WHEN a.discharge_location LIKE '%hospice%' THEN 'Hospice'
  END AS discharge_disposition,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los_mean_days,
  STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los_stddev_days
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
  AND a.admission_location = 'Transfer from other hospital'
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND (
    a.hospital_expire_flag = 1
    OR a.discharge_location LIKE '%home%'
    OR a.discharge_location LIKE '%hospice%'
  )
GROUP BY
  discharge_disposition
HAVING
  discharge_disposition IS NOT NULL
ORDER BY
  discharge_disposition;