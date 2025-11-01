WITH amipatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),
excluded_patients AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE (
    -- Shock codes
    (d.icd_version = 9 AND d.icd_code IN ('428.0', '785.51'))
    OR
    (d.icd_version = 10 AND d.icd_code IN ('I21.4', 'I22.1', 'I22.8', 'I22.9', 'R57.0', 'R57.8', 'R57.9'))
    OR
    -- Respiratory failure codes
    (d.icd_version = 9 AND d.icd_code = '518.81')
    OR
    (d.icd_version = 10 AND d.icd_code IN ('J96.0', 'J96.1', 'J96.2', 'J96.9'))
  )
),
eligible_patients AS (
  SELECT a.*
  FROM amipatients a
  LEFT JOIN excluded_patients e
    ON a.hadm_id = e.hadm_id
  WHERE e.hadm_id IS NULL
),
icu_day1 AS (
  SELECT DISTINCT
    i.hadm_id,
    CASE
      WHEN i.intime IS NOT NULL AND i.intime <= a.admittime + INTERVAL 24 HOUR THEN 'Yes'
      ELSE 'No'
    END AS ICU_day1
  FROM eligible_patients a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
),
final_analysis AS (
  SELECT
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '≤5'
      ELSE '>5'
    END AS LOS_group,
    i.ICU_day1,
    SUM(a.hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
    PERCENTILE_CONT(DATE_DIFF(a.dischtime, a.admittime, DAY), 0.5) AS median_LOS_days
  FROM eligible_patients a
  JOIN icu_day1 i
    ON a.hadm_id = i.hadm_id
  GROUP BY LOS_group, i.ICU_day1
)
SELECT
  LOS_group,
  ICU_day1,
  ROUND(mortality_rate, 2) AS mortality_rate,
  ROUND(median_LOS_days, 1) AS median_LOS_days
FROM final_analysis
ORDER BY LOS_group, ICU_day1;