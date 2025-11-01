WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN did.long_title LIKE '%septic shock%' THEN 1 ELSE 0 END) AS septic_shock,
    COUNT(DISTINCT CASE 
      WHEN did.long_title NOT LIKE '%sepsis%' 
       AND did.long_title NOT LIKE '%septic shock%' 
       THEN did.icd_code 
    END) AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE
    p.anchor_age BETWEEN 52 AND 62
    AND p.gender = 'M'
    AND (did.long_title LIKE '%sepsis%' OR did.long_title LIKE '%septic shock%')
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.admission_type, p.anchor_age, p.gender
),

sepsis_severity AS (
  SELECT
    *,
    CASE
      WHEN septic_shock = 1 THEN 'Septic Shock'
      ELSE 'Sepsis No Shock'
    END AS severity_group,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '≥8 days'
      ELSE 'Other'
    END AS los_category
  FROM
    sepsis_admissions
)

SELECT
  severity_group,
  los_category,
  admission_type,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent,
  AVG(comorbidity_count) AS mean_comorbidity_count
FROM
  sepsis_severity
WHERE
  los_category != 'Other'
GROUP BY
  severity_group,
  los_category,
  admission_type
ORDER BY
  severity_group,
  los_category,
  admission_type;