WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 83
    AND (LOWER(did.long_title) LIKE '%sepsis%' OR LOWER(did.long_title) LIKE '%septic%')
),
first_creatinine AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON l.itemid = dl.itemid
  JOIN sepsis_admissions sa ON l.hadm_id = sa.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON l.hadm_id = a.hadm_id
  WHERE dl.label = 'Creatinine'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= a.admittime
    AND l.charttime <= a.dischtime
)
SELECT MAX(valuenum) AS max_admission_creatinine
FROM first_creatinine
WHERE rn = 1;