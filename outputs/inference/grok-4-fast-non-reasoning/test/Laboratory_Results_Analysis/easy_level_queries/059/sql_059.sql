WITH sepsis_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age = '93'
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65%')
),
platelet_discharge AS (
  SELECT 
    sa.subject_id,
    sa.hadm_id,
    l.valuenum AS platelet_count
  FROM 
    sepsis_admissions sa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sa.subject_id = l.subject_id AND sa.hadm_id = l.hadm_id
  WHERE 
    l.itemid = 50592  -- Platelet count
    AND l.valuenum IS NOT NULL
    AND l.charttime >= sa.admittime
    AND l.charttime <= sa.dischtime
    AND DATE(l.charttime) = DATE(sa.dischtime)
)
SELECT 
  PERCENTILE_CONT(platelet_count, 0.75) AS p75_platelet_count
FROM 
  platelet_discharge;