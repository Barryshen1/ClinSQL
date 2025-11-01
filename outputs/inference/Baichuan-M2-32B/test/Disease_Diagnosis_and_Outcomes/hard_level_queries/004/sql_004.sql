WITH 
  -- Identify female inpatients aged 44-54 with ICH
  ich_admissions AS (
    SELECT 
      p.subject_id,
      p.anchor_year,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      a.admission_type,
      -- Compute age at admission
      TIMESTAMP_DIFF(a.admittime, 
                     DATE_SUB(CURRENT_DATE(), INTERVAL p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) YEAR), 
                     YEAR) AS age_at_admission
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND TIMESTAMP_DIFF(a.admittime, 
                         DATE_SUB(CURRENT_DATE(), INTERVAL p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) YEAR), 
                         YEAR) BETWEEN 44 AND 54
      -- ICH diagnosis: ICD-10 I60-I62 or ICD-9 430-432
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = a.hadm_id
          AND ((d.icd_version = 10 AND d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
               OR (d.icd_version = 9 AND d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
      )
  ),
  -- Compute composite risk score
  risk_scores AS (
    SELECT 
      subject_id,
      hadm_id,
      age_at_admission,
      admission_type,
      -- Age points
      CASE 
        WHEN age_at_admission BETWEEN 44 AND 49 THEN 0 
        WHEN age_at_admission BETWEEN 50 AND 54 THEN 1 
        ELSE NULL 
      END AS age_points,
      -- Admission type points
      CASE 
        WHEN admission_type = 'ELECTIVE' THEN 0 
        ELSE 1 
      END AS admit_type_points,
      -- Hypertension points (using ICD-10 I10 or ICD-9 401)
      MAX(CASE 
            WHEN d.icd_code = 'I10' AND d.icd_version = 10 THEN 1 
            WHEN d.icd_code = '401' AND d.icd_version = 9 THEN 1 
            ELSE 0 
          END) AS hypertension_points,
      -- Diabetes points (ICD-10 E11 or ICD-9 250)
      MAX(CASE 
            WHEN d.icd_code = 'E11' AND d.icd_version = 10 THEN 1 
            WHEN d.icd_code = '250' AND d.icd_version = 9 THEN 1 
            ELSE 0 
          END) AS diabetes_points,
      -- Total score (sum of points)
      CASE 
        WHEN age_at_admission BETWEEN 44 AND 49 THEN 0 
        WHEN age_at_admission BETWEEN 50 AND 54 THEN 1 
        ELSE 0 
      END +
      CASE 
        WHEN admission_type = 'ELECTIVE' THEN 0 
        ELSE 1 
      END +
      MAX(CASE 
            WHEN d.icd_code = 'I10' AND d.icd_version = 10 THEN 1 
            WHEN d.icd_code = '401' AND d.icd_version = 9 THEN 1 
            ELSE 0 
          END) +
      MAX(CASE 
            WHEN d.icd_code = 'E11' AND d.icd_version = 10 THEN 1 
            WHEN d.icd_code = '250' AND d.icd_version = 9 THEN 1 
            ELSE 0 
          END) AS total_score
    FROM 
      ich_admissions
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON ich_admissions.hadm_id = d.hadm_id
      AND ( (d.icd_code = 'I10' AND d.icd_version = 10) 
            OR (d.icd_code = '401' AND d.icd_version = 9) 
            OR (d.icd_code = 'E11' AND d.icd_version = 10) 
            OR (d.icd_code = '250' AND d.icd_version = 9) )
    GROUP BY subject_id, hadm_id, age_at_admission, admission_type
  ),
  -- Assign quartiles
  quartiles AS (
    SELECT 
      *,
      NTILE(4) OVER (ORDER BY total_score) AS risk_quartile
    FROM risk_scores
  ),
  -- Identify complications (cardiac and neurologic) using ICD codes
  complications AS (
    SELECT 
      subject_id,
      hadm_id,
      MAX(CASE 
            WHEN d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%' OR d.icd_code LIKE 'I47%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I49%' 
                 AND d.icd_version = 10 THEN 1 
            WHEN d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '412%' OR d.icd_code LIKE '413%' OR d.icd_code LIKE '414%' OR d.icd_code LIKE '427%' OR d.icd_code LIKE '428%' 
                 AND d.icd_version = 9 THEN 1 
            ELSE 0 
          END) AS cardiac_complication,
      MAX(CASE 
            WHEN d.icd_code LIKE 'G40%' OR d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'G93.7' 
                 AND d.icd_version = 10 THEN 1 
            WHEN d.icd_code LIKE '345%' OR d.icd_code LIKE '347%' OR d.icd_code LIKE '348%' 
                 AND d.icd_version = 9 THEN 1 
            ELSE 0 
          END) AS neuro_complication
    FROM 
      ich_admissions
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON ich_admissions.hadm_id = d.hadm_id
    GROUP BY subject_id, hadm_id
  ),
  -- Prepare data for final aggregation
  final_data_prep AS (
    SELECT 
      q.risk_quartile,
      q.subject_id,
      q.hadm_id,
      q.hospital_expire_flag,
      q.admittime,
      q.dischtime,
      c.cardiac_complication,
      c.neuro_complication,
      -- Compute LOS for survivors
      CASE WHEN q.hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY) END AS los_survivors
    FROM 
      quartiles q
    INNER JOIN ich_admissions i 
      ON q.subject_id = i.subject_id AND q.hadm_id = i.hadm_id
    LEFT JOIN complications c 
      ON q.subject_id = c.subject_id AND q.hadm_id = c.hadm_id
  )
  -- Compute metrics per quartile
  SELECT 
    risk_quartile,
    COUNT(*) AS patient_count,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    -- Mortality rate
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS mortality_rate,
    -- Cardiac complication rate
    SUM(cardiac_complication) * 1.0 / COUNT(*) AS cardiac_complication_rate,
    -- Neuro complication rate
    SUM(neuro_complication) * 1.0 / COUNT(*) AS neuro_complication_rate,
    -- Median LOS for survivors
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_survivors) AS median_los_survivors
  FROM final_data_prep
  GROUP BY risk_quartile
  ORDER BY risk_quartile;