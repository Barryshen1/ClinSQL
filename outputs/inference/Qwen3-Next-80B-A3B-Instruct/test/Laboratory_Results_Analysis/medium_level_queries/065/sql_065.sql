WITH amipatients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
),
first_troponin AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
  FROM amipatients a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents l
    ON a.hadm_id = l.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) IN ('ng/ml', 'ng/mL')
    AND l.valuenum > 0.04
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3_troponin_t
FROM first_troponin
WHERE rn = 1;