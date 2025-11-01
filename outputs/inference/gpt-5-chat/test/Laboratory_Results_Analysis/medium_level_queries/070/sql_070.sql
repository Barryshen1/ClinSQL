WITH chest_pain_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code
   AND dx.icd_version = dxd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(dxd.long_title) LIKE '%chest pain%'
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime,
         le.valuenum, le.ref_range_upper, le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT
    cpa.subject_id,
    cpa.hadm_id,
    tro.valuenum,
    tro.ref_range_upper,
    tro.charttime,
    tro.valueuom
  FROM chest_pain_admissions cpa
  JOIN troponin_labs tro
    ON cpa.subject_id = tro.subject_id
   AND cpa.hadm_id = tro.hadm_id
  QUALIFY charttime = MIN(charttime) OVER (PARTITION BY cpa.hadm_id)
),
elevated_first_trop AS (
  SELECT *
  FROM first_trop
  WHERE (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
     OR (ref_range_upper IS NULL AND valuenum > 0.04)
)
SELECT
  PERCENTILE_CONT(valuenum, 0.25) AS p25,
  PERCENTILE_CONT(valuenum, 0.5)  AS p50,
  PERCENTILE_CONT(valuenum, 0.75) AS p75,
  MAX(valuenum) - MIN(valuenum)   AS value_range
FROM elevated_first_trop;