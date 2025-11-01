WITH 
-- Identify index admissions
index_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    a.admission_type = 'Emergency'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.insurance = 'Medicare'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_code LIKE '577.0%'  -- Acute pancreatitis
    )
),

-- Identify readmissions
readmissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    a.admission_type = 'Emergency'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.insurance = 'Medicare'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_code LIKE '577.0%'  -- Acute pancreatitis
    )
    AND a.admittime BETWEEN 
      (SELECT dischtime FROM index_admissions WHERE subject_id = a.subject_id AND hadm_id = (SELECT MAX(hadm_id) FROM index_admissions WHERE subject_id = a.subject_id)) 
      + INTERVAL 0 DAY 
    AND (SELECT dischtime FROM index_admissions WHERE subject_id = a.subject_id AND hadm_id = (SELECT MAX(hadm_id) FROM index_admissions WHERE subject_id = a.subject_id)) 
      + INTERVAL 30 DAY
),

-- Identify index admissions with readmission status
index_admissions_with_readmission AS (
  SELECT 
    ia.hadm_id,
    ia.subject_id,
    ia.dischtime,
    ia.admittime,
    DATE_DIFF(ia.dischtime, ia.admittime, DAY) AS index_los,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM readmissions r
        WHERE 
          r.subject_id = ia.subject_id
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM 
    index_admissions ia
)

-- Calculate 30-day readmission rate, median index LOS, and percent stays > 9 days
SELECT 
  SUM(readmitted) / COUNT(*) AS thirty_day_readmission_rate,
  APPROX_QUANTILES(index_los, 0.5)[OFFSET(1)] AS median_index_los,
  AVG(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) * 100 AS percent_stays_greater_than_nine_days
FROM 
  index_admissions_with_readmission;