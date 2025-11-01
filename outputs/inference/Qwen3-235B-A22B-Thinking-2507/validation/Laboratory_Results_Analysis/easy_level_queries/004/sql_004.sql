WITH sepsis_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) = 76
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('0380','0381','0382','0383','0384','0388','0389','1125','5721','78552','99591','99592'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R652%'))
        )
    )
),
platelet_measurements AS (
  SELECT 
    sa.hadm_id,
    l.valuenum AS platelet_value
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE 
    d.label = 'Platelets'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= sa.admittime
    AND l.charttime < DATETIME_ADD(sa.admittime, INTERVAL 1 DAY)
),
admission_averages AS (
  SELECT 
    hadm_id,
    AVG(platelet_value) AS avg_platelet
  FROM platelet_measurements
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(avg_platelet, 100)[OFFSET(50)] AS median_platelet
FROM admission_averages;