WITH 
-- Identify target population (male, 40-50, hemorrhagic stroke)
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN (
          SELECT 
            icd_code 
          FROM 
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE 
            long_title LIKE '%Hemorrhagic stroke%'
        )
    )
),

-- Identify abnormal labs within 72 hours of admission
abnormal_labs AS (
  SELECT 
    le.hadm_id,
    le.subject_id,
    le.itemid,
    le.charttime,
    le.value,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    CASE 
      WHEN le.valuenum IS NOT NULL AND 
           (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper) 
      THEN 1 
      ELSE 0 
    END AS is_abnormal
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON le.hadm_id = a.hadm_id
  WHERE 
    le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),

-- Calculate lab instability score (count of unique abnormal labs)
lab_instability_score AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT itemid) AS score
  FROM 
    abnormal_labs
  WHERE 
    is_abnormal = 1
  GROUP BY 
    hadm_id
),

-- Stratify into quartiles based on lab instability score
quartiles AS (
  SELECT 
    hadm_id,
    score,
    NTILE(4) OVER (ORDER BY score) AS quartile
  FROM 
    lab_instability_score
),

-- Prepare for final aggregation
final_data AS (
  SELECT 
    tp.hadm_id,
    tp.subject_id,
    tp.dod,
    a.dischtime,
    a.admittime,
    COALESCE(q.quartile, 0) AS quartile,
    COALESCE(lis.score, 0) AS lab_instability_score
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.hadm_id = a.hadm_id
  LEFT JOIN 
    quartiles q ON tp.hadm_id = q.hadm_id
  LEFT JOIN 
    lab_instability_score lis ON tp.hadm_id = lis.hadm_id
)

-- Final aggregation
SELECT 
  quartile,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los,
  SUM(CASE WHEN dod IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate,
  SUM(lab_instability_score) / COUNT(*) AS avg_abnormal_labs_per_patient
FROM 
  final_data
GROUP BY 
  quartile
ORDER BY 
  quartile;