WITH ischemic_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%ischemic stroke%' 
    AND p.gender = 'F'
    AND p.anchor_age >= 65
),
glucose_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%'
    AND LOWER(fluid) = 'serum'
),
glucose_first_per_admission AS (
  SELECT le.subject_id,
         le.hadm_id,
         le.charttime,
         le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN ischemic_admissions ia
    ON le.subject_id = ia.subject_id
   AND le.hadm_id = ia.hadm_id
  JOIN glucose_items gi
    ON le.itemid = gi.itemid
  WHERE le.charttime >= (SELECT admittime
                          FROM `physionet-data.mimiciv_3_1_hosp.admissions`
                          WHERE hadm_id = ia.hadm_id)
    AND le.charttime <= (SELECT dischtime
                          FROM `physionet-data.mimiciv_3_1_hosp.admissions`
                          WHERE hadm_id = ia.hadm_id)
    AND le.valuenum IS NOT NULL
    AND (LOWER(le.valueuom) = 'mg/dl' OR LOWER(le.valueuom) LIKE '%mg/dl%')
  QUALIFY ROW_NUMBER() OVER (
            PARTITION BY le.subject_id, le.hadm_id
            ORDER BY le.charttime
          ) = 1
)
SELECT
  quantiles[OFFSET(74)] AS p75_mg_per_dl
FROM (
  SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM glucose_first_per_admission
) AS q;