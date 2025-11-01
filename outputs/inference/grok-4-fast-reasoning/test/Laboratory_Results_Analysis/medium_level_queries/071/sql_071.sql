WITH age_calc AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    FLOOR(
      DATE_DIFF(
        DATE(a.admittime), 
        DATE(CAST(p.anchor_year AS STRING) || '-01-01'), 
        DAY
      ) / 365.25
    ) + p.anchor_age AS age_at_admit
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
),
acs_admissions AS (
  SELECT 
    ac.*
  FROM 
    age_calc ac
  WHERE 
    ac.gender = 'F'
    AND ac.age_at_admit BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.subject_id = ac.subject_id 
        AND di.hadm_id = ac.hadm_id
        AND (
          (di.icd_version = 10 AND (di.icd_code = 'I200' OR di.icd_code LIKE 'I21%'))
          OR
          (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code = '4111'))
        )
    )
),
initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE 
    le.itemid = 51006 
    AND le.valuenum IS NOT NULL
)
SELECT 
  troponin_category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS avg_hospital_los_days
FROM (
  SELECT 
    aa.*,
    it.valuenum,
    TIMESTAMP_DIFF(aa.dischtime, aa.admittime, HOUR) / 24.0 AS los_days,
    CASE 
      WHEN it.valuenum <= 0.01 THEN 'Normal'
      WHEN it.valuenum > 0.01 AND it.valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM 
    acs_admissions aa
  INNER JOIN 
    initial_troponin it
  ON 
    aa.hadm_id = it.hadm_id 
    AND it.rn = 1
)
GROUP BY 
  troponin_category
ORDER BY 
  count_admissions DESC;