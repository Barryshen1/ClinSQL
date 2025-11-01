WITH stroke_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON diag.icd_code = ddi.icd_code
    AND diag.icd_version = ddi.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 50
    AND LOWER(ddi.long_title) LIKE '%stroke%'
    AND LOWER(ddi.long_title) LIKE '%ischemic%'
),
hemo_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) = 'hemoglobin'
    AND le.valuenum IS NOT NULL
)
SELECT MIN(min_hb) AS overall_min_hemoglobin
FROM (
  SELECT sa.hadm_id, MIN(hl.valuenum) AS min_hb
  FROM stroke_admissions sa
  JOIN hemo_labs hl
    ON sa.subject_id = hl.subject_id
    AND sa.hadm_id = hl.hadm_id
    AND hl.charttime >= sa.admittime
    AND hl.charttime <= sa.admittime + INTERVAL 24 HOUR
  GROUP BY sa.hadm_id
) t;