WITH acs_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 57
    AND d.icd_code LIKE 'I21%'
    AND d.icd_version = 10  -- Focus on ICD-10 for ACS
),
troponin_mins AS (
  SELECT 
    aa.hadm_id,
    MIN(le.valuenum) AS min_troponin
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.charttime >= aa.admittime
    AND li.label LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
  GROUP BY aa.hadm_id
  HAVING min_troponin IS NOT NULL
)
SELECT 
  MIN(min_troponin) AS minimum_serum_troponin
FROM troponin_mins;