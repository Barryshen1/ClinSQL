WITH acs_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND diag.icd_code IN ('I200', 'I210', 'I211', 'I212', 'I213', 'I214', 'I219')
    AND diag.icd_version = 10
),
nadir_troponin AS (
  SELECT 
    adm.hadm_id,
    MIN(lab.valuenum) AS nadir_troponin
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON aa.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.hadm_id = lab.hadm_id
  WHERE lab.itemid IN (50189, 50590)
    AND lab.valuenum IS NOT NULL
    AND lab.charttime >= adm.admittime
    AND lab.charttime <= adm.dischtime
  GROUP BY adm.hadm_id
)
SELECT 
  APPROX_QUANTILES(nt.nadir_troponin, 1000)[OFFSET(250)] AS p25_nadir_troponin
FROM nadir_troponin nt;