WITH acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      LOWER(di.long_title) LIKE LOWER('%acute coronary syndrome%')
      OR LOWER(di.long_title) LIKE LOWER('%myocardial infarction%')
      OR LOWER(di.long_title) LIKE LOWER('%unstable angina%')
    )
),
first_troponin AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM acs_admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.labevents l ON a.hadm_id = l.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Troponin I'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.04
    AND l.charttime >= a.admittime
    AND l.charttime <= a.dischtime
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(valuenum) AS mean_troponin,
  STDDEV(valuenum) AS sd_troponin,
  MIN(valuenum) AS min_troponin,
  MAX(valuenum) AS max_troponin
FROM first_troponin
WHERE rn = 1;