WITH 
troponin_i AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE 
    di.label LIKE '%Troponin I%'
    AND le.valuenum IS NOT NULL
),

acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE 
    di.icd_code LIKE '%410%'  
    AND a.admission_type IN ('elective', 'urgent', 'emergency')  
),

patient_demographics AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
)

SELECT 
  COUNT(ti.valuenum) AS count,
  AVG(ti.valuenum) AS mean,
  APPROX_QUANTILES(ti.valuenum, 100)[SAFE_ORDINAL(50)] AS median,
  APPROX_QUANTILES(ti.valuenum, 100)[SAFE_ORDINAL(25)] AS q1,
  APPROX_QUANTILES(ti.valuenum, 100)[SAFE_ORDINAL(75)] AS q3
FROM 
  troponin_i ti
  JOIN acs_admissions aa ON ti.hadm_id = aa.hadm_id
  JOIN patient_demographics pd ON ti.subject_id = pd.subject_id
WHERE 
  ti.valuenum > (SELECT APPROX_QUANTILES(valuenum, 100)[SAFE_ORDINAL(99)] 
                  FROM troponin_i);