SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'Discharged to Hospice'
    WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'Discharged Home'
  END AS discharge_group,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los,
  STDDEV_POP(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  ON a.hadm_id = icu.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 75 AND 85
  AND icu.stay_id IS NULL
  AND (
    a.hospital_expire_flag = 1
    OR UPPER(a.discharge_location) LIKE '%HOSPICE%'
    OR UPPER(a.discharge_location) LIKE 'HOME%'
  )
GROUP BY discharge_group
ORDER BY discharge_group;