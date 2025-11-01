WITH ischemic_stroke_patients AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Ischemic stroke%' AND diag.icd_version = 10
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, ad.hadm_id, ad.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN ischemic_stroke_patients isp
    ON p.subject_id = isp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON isp.hadm_id = ad.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age = 82
),
glucose_measurements AS (
  SELECT ep.subject_id, ep.hadm_id, lb.valuenum, lb.charttime, ad.admittime,
         ROW_NUMBER() OVER (PARTITION BY ep.hadm_id ORDER BY lb.charttime) as rn
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lb
    ON ep.hadm_id = lb.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON ep.hadm_id = ad.hadm_id
  WHERE lb.itemid = 50809  
    AND lb.charttime >= ad.admittime
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS glucose_75th_percentile
FROM glucose_measurements
WHERE rn = 1;