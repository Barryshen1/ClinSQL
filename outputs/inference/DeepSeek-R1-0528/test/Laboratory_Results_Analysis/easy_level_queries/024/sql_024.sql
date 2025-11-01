WITH sepsis_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
          OR 
          (d.icd_version = 10 AND d.icd_code IN ('A419', 'R6520', 'R6521'))
        )
    )
),
first_platelet AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS platelet_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN sepsis_admissions sa
    ON l.hadm_id = sa.hadm_id
  WHERE 
    l.itemid = 51265  -- Platelet Count
    AND l.valuenum IS NOT NULL
    AND l.charttime >= sa.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
)
SELECT 
  STDDEV(platelet_count) AS platelet_sd
FROM first_platelet;