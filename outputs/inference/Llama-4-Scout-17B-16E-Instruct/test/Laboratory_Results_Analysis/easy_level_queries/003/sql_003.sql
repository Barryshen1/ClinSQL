WITH 
troponin_item AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin%'
),

acs_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    a.subject_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.hadm_id = di.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    di.icd_code LIKE '%410%'  
    AND p.gender = 'M'
    AND p.anchor_age = 64
),

peak_troponin AS (
  SELECT 
    MAX(le.valuenum) AS peak_troponin
  FROM 
    acs_admissions a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
  JOIN 
    troponin_item ti ON le.itemid = ti.itemid
)

SELECT 
  APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS percentile_75
FROM 
  peak_troponin;