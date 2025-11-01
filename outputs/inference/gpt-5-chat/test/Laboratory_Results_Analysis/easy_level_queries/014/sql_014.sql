WITH gi_bleed_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age = 45
    AND (
      LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(dd.long_title) LIKE '%gi bleed%'
      OR LOWER(dd.long_title) LIKE '%melena%'
      OR LOWER(dd.long_title) LIKE '%hematemesis%'
    )
),
discharge_day_hemoglobin AS (
  SELECT ga.subject_id, ga.hadm_id, le.valuenum
  FROM gi_bleed_admissions ga
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ga.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) = 'hemoglobin'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND DATE(le.charttime) = DATE(ga.dischtime)
)
SELECT
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS hemoglobin_75th_percentile_g_dl
FROM discharge_day_hemoglobin;