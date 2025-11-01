WITH copd_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '496%'))
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
    )
),
creatinine_peaks AS (
  SELECT 
    l.hadm_id,
    MAX(l.valuenum) AS peak_creat
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN copd_admissions c
    ON l.hadm_id = c.hadm_id
  WHERE l.itemid = 50912  -- Serum creatinine itemid
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'mg/dL'
  GROUP BY l.hadm_id
)
SELECT MAX(peak_creat) AS max_peak_creat
FROM creatinine_peaks;