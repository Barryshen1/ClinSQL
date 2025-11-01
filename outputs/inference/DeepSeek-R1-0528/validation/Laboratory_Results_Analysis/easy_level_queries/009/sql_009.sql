WITH acs_female_admissions AS (
  SELECT DISTINCT 
    d.subject_id, 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = 'I20.0'))
      OR 
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '411.1'))
    )
),
troponin_nadir AS (
  SELECT 
    l.hadm_id,
    MIN(l.valuenum) AS nadir_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN acs_female_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE 
    l.itemid IN (50911, 51003, 50912)  -- Troponin I tests
    AND l.valuenum IS NOT NULL          -- Ensure numeric values
  GROUP BY l.hadm_id
)
SELECT 
  APPROX_QUANTILES(nadir_troponin, 100)[OFFSET(25)] AS percentile_25_nadir_troponin
FROM troponin_nadir;