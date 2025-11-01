WITH acs_hadm AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 64
    AND (
      (dx.icd_version = 9 AND (
         dx.icd_code LIKE '410%' OR  -- AMI
         dx.icd_code LIKE '411%'     -- other ACS
      ))
      OR
      (dx.icd_version = 10 AND (
         dx.icd_code LIKE 'I20%' OR  -- angina
         dx.icd_code LIKE 'I21%' OR  -- AMI
         dx.icd_code LIKE 'I22%' OR  -- Subsequent AMI
         dx.icd_code LIKE 'I23%' OR  -- complications post-AMI
         dx.icd_code LIKE 'I24%' OR  -- other ACS
         dx.icd_code LIKE 'I25%'     -- chronic ischemic heart disease
      ))
    )
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON le.hadm_id = adm.hadm_id
  WHERE LOWER(di.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= adm.admittime
    AND le.charttime <= adm.dischtime
),
peak_trop_per_hadm AS (
  SELECT ah.subject_id, ah.hadm_id, MAX(tl.valuenum) AS peak_troponin
  FROM acs_hadm ah
  JOIN troponin_labs tl
    ON ah.hadm_id = tl.hadm_id
  GROUP BY ah.subject_id, ah.hadm_id
)
SELECT
  PERCENTILE_CONT(peak_troponin, 0.75) OVER() AS perc75_peak_troponin
FROM peak_trop_per_hadm
LIMIT 1;