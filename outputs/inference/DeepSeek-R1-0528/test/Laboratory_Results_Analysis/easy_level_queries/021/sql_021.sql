WITH male_pneumonia_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code BETWEEN '480' AND '486') 
          OR 
          (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^J1[2-8]'))
        )
    )
),
last_glucose AS (
  SELECT 
    g.hadm_id,
    l.valuenum AS glucose_value
  FROM male_pneumonia_admissions g
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON g.hadm_id = l.hadm_id
  WHERE 
    l.itemid IN (50809, 50931)   -- Serum glucose item IDs
    AND l.valuenum IS NOT NULL   -- Ensure numeric value exists
    AND l.charttime <= g.dischtime  -- Measurement before discharge
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY g.hadm_id 
    ORDER BY l.charttime DESC, l.labevent_id DESC
  ) = 1  -- Last glucose per admission
)
SELECT 
  APPROX_QUANTILES(glucose_value, 100)[OFFSET(75)] AS p75_glucose
FROM last_glucose;