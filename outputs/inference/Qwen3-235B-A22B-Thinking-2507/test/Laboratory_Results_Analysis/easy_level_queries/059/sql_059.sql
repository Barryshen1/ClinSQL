WITH sepsis_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%')
    AND a.dischtime IS NOT NULL
),
platelet_on_discharge AS (
  SELECT 
    sa.hadm_id,
    le.valuenum AS platelet_count,
    ROW_NUMBER() OVER (
      PARTITION BY sa.hadm_id 
      ORDER BY le.charttime DESC
    ) AS rn
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Platelets'
    AND DATE(le.charttime) = DATE(sa.dischtime)
    AND le.valuenum IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(platelet_count, 0.75) OVER () AS percentile_75
FROM platelet_on_discharge
WHERE rn = 1
LIMIT 1;