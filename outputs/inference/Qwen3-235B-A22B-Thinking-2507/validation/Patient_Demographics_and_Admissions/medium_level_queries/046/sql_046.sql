WITH patient_admissions AS (
  SELECT
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    pat.gender,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
),
icu_admissions AS (
  SELECT 
    pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pa.hadm_id = icu.hadm_id
  WHERE 
    pa.gender = 'F' 
    AND pa.age_at_admission BETWEEN 87 AND 97
    AND pa.admittime IS NOT NULL
    AND pa.dischtime IS NOT NULL
),
outcome_groups AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOSPICE-HOME') THEN 'Home'
      WHEN discharge_location IN (
        'HOSPICE', 'HOSPICE-MEDICAL CENTER', 'HOSPICE-ASSISTED LIVING',
        'SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP', 'SNF',
        'INTERMEDIATE CARE FACILITY', 'OTHER FACILITY'
      ) THEN 'Facility'
      ELSE NULL
    END AS outcome_group
  FROM icu_admissions
)
SELECT
  outcome_group,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  (SUM(CASE WHEN los_days < 10 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percent_los_lt_10
FROM outcome_groups
WHERE outcome_group IS NOT NULL
GROUP BY outcome_group
ORDER BY 
  CASE outcome_group
    WHEN 'In-hospital death' THEN 1
    WHEN 'Home' THEN 2
    WHEN 'Facility' THEN 3
  END;