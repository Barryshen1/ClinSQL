WITH female_pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code
   AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'F'
    AND (
      (diag.icd_version = 9 AND (
          diag.icd_code LIKE '480%' OR diag.icd_code LIKE '481%' OR diag.icd_code LIKE '482%' OR
          diag.icd_code LIKE '483%' OR diag.icd_code LIKE '484%' OR diag.icd_code LIKE '485%' OR
          diag.icd_code LIKE '486%'
      ))
      OR (diag.icd_version = 10 AND (
          diag.icd_code LIKE 'J12%' OR diag.icd_code LIKE 'J13%' OR diag.icd_code LIKE 'J14%' OR
          diag.icd_code LIKE 'J15%' OR diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%' OR
          diag.icd_code LIKE 'J18%'
      ))
    )
),
creatinine_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(dlab.label) LIKE '%creatinine%'
    AND LOWER(dlab.fluid) IN ('blood', 'serum')
),
daily_avg_creatinine AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    DATE(c.charttime) AS lab_date,
    AVG(c.valuenum) AS avg_creatinine
  FROM creatinine_labs c
  JOIN female_pneumonia_admissions fpa
    ON c.subject_id = fpa.subject_id AND c.hadm_id = fpa.hadm_id
  GROUP BY c.subject_id, c.hadm_id, DATE(c.charttime)
),
min_daily_avg_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(avg_creatinine) AS min_avg_creatinine
  FROM daily_avg_creatinine
  GROUP BY subject_id, hadm_id
)
SELECT MIN(min_avg_creatinine) AS cohort_min_24h_avg_creatinine
FROM min_daily_avg_per_admission;