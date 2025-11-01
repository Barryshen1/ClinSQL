WITH first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      di.icd_code LIKE 'I21%' 
      OR di.icd_code LIKE 'I22%' 
      OR di.icd_code LIKE 'I23%'
    )
    AND LOWER(d.label) LIKE '%troponin%t%'
    AND LOWER(d.label) LIKE '%high%'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
)
SELECT 
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS median_troponin_ngml,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS q1_troponin_ngml,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] AS q3_troponin_ngml,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] - APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS iqr_troponin_ngml
FROM first_troponin
WHERE rn = 1;