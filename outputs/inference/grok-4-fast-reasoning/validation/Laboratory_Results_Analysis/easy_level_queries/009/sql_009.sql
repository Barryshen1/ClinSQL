WITH acs_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (
      (d.icd_version = '9' 
       AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '4111%'))
      OR (d.icd_version = '10' 
          AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),
nadir_troponin AS (
  SELECT 
    c.hadm_id,
    MIN(l.valuenum) AS nadir_trop
  FROM acs_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON c.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON l.itemid = li.itemid
  WHERE l.valuenum IS NOT NULL
    AND LOWER(li.label) LIKE '%troponin%'
    AND l.charttime >= a.admittime
    AND (a.dischtime IS NULL OR l.charttime <= a.dischtime)
  GROUP BY c.hadm_id
)
SELECT 
  PERCENTILE_CONT(nadir_trop, 0.25) AS p25_nadir_troponin
FROM nadir_troponin;