WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admission_location,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND adm.admission_location LIKE 'TRANSFER FROM HOSPITAL%'
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN UPPER(discharge_location) LIKE 'HOME%' THEN 'Home'
    WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
  END AS discharge_category,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days
FROM cohort
WHERE (hospital_expire_flag = 1
       OR UPPER(discharge_location) LIKE 'HOME%'
       OR UPPER(discharge_location) LIKE '%HOSPICE%')
GROUP BY discharge_category
ORDER BY discharge_category;