WITH 
  -- Define patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      p.gender,
      p.anchor_age,
      d.icd_code,
      d.long_title AS diagnosis
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON a.hadm_id = di.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 65 AND 75
      AND d.long_title LIKE '%Acute pancreatitis%'
  ),

  -- Calculate lab instability scores
  lab_instability AS (
    SELECT 
      hadm_id,
      -- Simplified lab instability score calculation for demonstration
      AVG(valuenum) AS instability_score
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE 
      itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category = 'Lab')
    GROUP BY 
      hadm_id
  ),

  -- Calculate outcomes
  outcomes AS (
    SELECT 
      poi.hadm_id,
      poi.subject_id,
      li.instability_score,
      a.los,
      CASE 
        WHEN a.deathtime IS NOT NULL THEN 1 
        ELSE 0 
      END AS mortality
    FROM 
      patients_of_interest poi
    JOIN 
      lab_instability li ON poi.hadm_id = li.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON poi.hadm_id = a.hadm_id
  ),

  -- Stratify by quintiles
  quintiles AS (
    SELECT 
      hadm_id,
      instability_score,
      los,
      mortality,
      NTILE(5) OVER (ORDER BY instability_score) AS quintile
    FROM 
      outcomes
  ),

  -- Critical labs
  critical_labs AS (
    SELECT 
      hadm_id,
      CASE 
        WHEN valuenum > 100 OR valuenum < 50 THEN 1 
        ELSE 0 
      END AS has_critical_labs
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE 
      itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category = 'Lab')
  )

-- Final output refined
SELECT 
  q.quintile,
  COUNT(q.hadm_id) AS count,
  AVG(q.instability_score) AS mean_instability,
  AVG(q.los) AS mean_los,
  AVG(q.mortality) AS mortality_rate,
  SUM(CASE WHEN cl.has_critical_labs THEN 1 ELSE 0 END) * 100.0 / COUNT(q.hadm_id) AS percent_critical_labs
FROM 
  quintiles q
  LEFT JOIN critical_labs cl ON q.hadm_id = cl.hadm_id
GROUP BY 
  q.quintile
ORDER BY 
  q.quintile;