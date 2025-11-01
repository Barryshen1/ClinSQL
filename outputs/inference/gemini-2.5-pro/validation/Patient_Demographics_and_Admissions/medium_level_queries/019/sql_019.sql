WITH admission_details AS (
  SELECT
    adm.hadm_id,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
      WHEN adm.discharge_location LIKE 'HOME%' THEN 'Discharged Home'
      WHEN adm.discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS stddev_los_days
FROM
  admission_details
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;