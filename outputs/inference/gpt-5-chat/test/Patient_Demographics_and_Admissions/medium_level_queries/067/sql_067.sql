WITH med_service AS (
  SELECT
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
base AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.deathtime,
    adm.discharge_location,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN med_service ms
    ON adm.hadm_id = ms.hadm_id
   AND ms.rn = 1
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND ms.curr_service LIKE 'MED%'
)
, categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_group
  FROM base
)
SELECT
  discharge_group,
  COUNT(*) AS n,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_los_ge_7,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END), COUNT(*)) AS prop_los_ge_14,
  SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_los_7d
FROM categorized
WHERE discharge_group IN ('Home','Hospice','In-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;