WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) >= 8 THEN '>=8'
      ELSE 'Other'
    END AS los_group,
    c.charlson_comorbidity_index AS charlson,
    CASE
      WHEN c.charlson_comorbidity_index <= 3 THEN '<=3'
      WHEN c.charlson_comorbidity_index BETWEEN 4 AND 5 THEN '4-5'
      WHEN c.charlson_comorbidity_index > 5 THEN '>5'
      ELSE NULL
    END AS charlson_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_derived.charlson` c
    ON a.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
    )
)
SELECT 
  los_group,
  charlson_group,
  COUNT(*) AS n_patients,
  SUM(hospital_expire_flag) AS n_mortality,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  ROUND(AVG(los), 2) AS avg_los_absolute,
  COUNTIF(discharge_location = 'HOME') AS home_count,
  ROUND(100 * COUNTIF(discharge_location = 'HOME') / COUNT(*), 2) AS home_percent,
  COUNTIF(discharge_location LIKE '%REHAB%') AS rehab_count,
  ROUND(100 * COUNTIF(discharge_location LIKE '%REHAB%') / COUNT(*), 2) AS rehab_percent,
  COUNTIF(discharge_location LIKE '%SNF%') AS snf_count,
  ROUND(100 * COUNTIF(discharge_location LIKE '%SNF%') / COUNT(*), 2) AS snf_percent,
  COUNTIF(discharge_location LIKE '%HOSPICE%') AS hospice_count,
  ROUND(100 * COUNTIF(discharge_location LIKE '%HOSPICE%') / COUNT(*), 2) AS hospice_percent
FROM cohort
WHERE los_group != 'Other'
GROUP BY los_group, charlson_group
ORDER BY los_group, charlson_group;