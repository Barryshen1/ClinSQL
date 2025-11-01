WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(d_icd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(d_icd.long_title) LIKE '%unstable angina%'
     OR LOWER(d_icd.long_title) LIKE '%acute ischemic heart disease%'
     OR LOWER(d_icd.long_title) LIKE '%angina pectoris%'
     OR LOWER(d_icd.long_title) LIKE '%coronary artery disease%'
     OR d_icd.icd_code IN ('I21', 'I22', 'I24', 'I20', 'I25')
     OR d_icd.icd_code IN ('410', '411', '413', '414')
),
first_troponin_t AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0
)
SELECT 
  SUM(CASE WHEN ftt.valuenum <= 0.04 THEN 1 ELSE 0 END) AS normal_count,
  SUM(CASE WHEN ftt.valuenum > 0.04 AND ftt.valuenum <= 0.1 THEN 1 ELSE 0 END) AS borderline_count,
  SUM(CASE WHEN ftt.valuenum > 0.1 THEN 1 ELSE 0 END) AS elevated_count
FROM first_troponin_t ftt
JOIN acs_admissions aa ON ftt.hadm_id = aa.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON aa.hadm_id = a.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 79 AND 89
  AND ftt.rn = 1;