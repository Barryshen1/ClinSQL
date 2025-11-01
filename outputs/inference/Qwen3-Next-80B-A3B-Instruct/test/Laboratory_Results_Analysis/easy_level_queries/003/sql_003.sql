WITH male_acs_admissions AS (
  SELECT DISTINCT p.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND (dicd.icd_code LIKE 'I21%'  -- Acute myocardial infarction
         OR dicd.icd_code LIKE 'I22%'  -- Subsequent MI
         OR dicd.icd_code LIKE 'I24%')  -- Other acute ischemic heart disease
),
peak_troponin_per_admission AS (
  SELECT 
    ma.hadm_id,
    MAX(le.valuenum) AS peak_troponin
  FROM male_acs_admissions ma
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON ma.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0  -- Exclude implausible negative or zero values
  GROUP BY ma.hadm_id
)
SELECT APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS p75_peak_troponin
FROM peak_troponin_per_admission
WHERE peak_troponin IS NOT NULL;