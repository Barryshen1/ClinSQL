WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  WHERE diag.icd_code LIKE 'I21%' OR diag.icd_code = 'I20.0'
),
male_acs_64 AS (
  SELECT adm.subject_id, adm.hadm_id
  FROM acs_admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 64
),
peak_troponin AS (
  SELECT le.hadm_id, MAX(le.valuenum) AS peak_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN male_acs_64 macs
    ON le.hadm_id = macs.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON le.hadm_id = adm2.hadm_id
  WHERE dli.label LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN adm2.admittime AND adm2.dischtime
  GROUP BY le.hadm_id
)
SELECT APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS percentile_75
FROM peak_troponin;