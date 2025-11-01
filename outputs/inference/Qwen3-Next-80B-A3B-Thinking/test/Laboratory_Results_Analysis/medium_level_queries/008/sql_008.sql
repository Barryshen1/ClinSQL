WITH suspected_acs AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE d.seq_num = 1
    AND (
      d_diag.long_title LIKE '%acute coronary syndrome%'
      OR d_diag.long_title LIKE '%myocardial infarction%'
      OR d_diag.long_title LIKE '%unstable angina%'
    )
),

male_87_97 AS (
  SELECT 
    sa.hadm_id, 
    sa.subject_id, 
    sa.admittime, 
    sa.hospital_expire_flag
  FROM suspected_acs sa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON sa.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM sa.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 87 AND 97
),

troponin_events AS (
  SELECT 
    le.hadm_id, 
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.label LIKE '%TROPONIN T%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),

final_data AS (
  SELECT 
    m.hadm_id, 
    m.hospital_expire_flag, 
    te.valuenum
  FROM male_87_97 m
  INNER JOIN troponin_events te
    ON m.hadm_id = te.hadm_id
)

SELECT
  CASE
    WHEN valuenum < 0.01 THEN 'Normal/Minimal'
    WHEN valuenum >= 0.01 AND valuenum < 0.04 THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM final_data
GROUP BY troponin_category
ORDER BY troponin_category;