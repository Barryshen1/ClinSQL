WITH sepsis_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    -- ICD-9 sepsis codes
    (d.icd_version = 9 AND (
        d.icd_code IN ('99591','99592','78552')
        OR d.icd_code LIKE '038%'    -- septicemia
        OR d.icd_code LIKE '9959%'   -- systemic inflammatory response syndrome
    ))
    -- ICD-10 sepsis codes
    OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'A40%'  -- streptococcal sepsis
        OR d.icd_code LIKE 'A41%' -- other sepsis
    ))
),
male_sepsis AS (
  SELECT p.subject_id
  FROM sepsis_patients s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
platelet_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.label = 'Platelet Count'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
),
peak_platelet_per_patient AS (
  SELECT m.subject_id, MAX(pl.valuenum) AS peak_platelet
  FROM male_sepsis m
  JOIN platelet_labs pl
    ON m.subject_id = pl.subject_id
  GROUP BY m.subject_id
)
SELECT
  PERCENTILE_CONT(peak_platelet, 0.75) OVER() AS pct75_peak_platelet
FROM peak_platelet_per_patient
LIMIT 1;