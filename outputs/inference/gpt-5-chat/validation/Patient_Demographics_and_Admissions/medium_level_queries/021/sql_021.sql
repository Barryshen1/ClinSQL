WITH surg_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.services`
  WHERE UPPER(curr_service) LIKE '%SURG%'
),
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN surg_admissions sa
    ON adm.hadm_id = sa.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
classified AS (
  SELECT
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN UPPER(discharge_location) LIKE 'HOME%' THEN 'Discharged home'
      ELSE 'Discharged to facility'
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_LOS_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_LOS_days,
  ROUND(100.0 * COUNTIF(los_days <= 7) / COUNT(*), 1) AS pct_LOS_le_7_days
FROM classified
GROUP BY discharge_group
ORDER BY discharge_group;