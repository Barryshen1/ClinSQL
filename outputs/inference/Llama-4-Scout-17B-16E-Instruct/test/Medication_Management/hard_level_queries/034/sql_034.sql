WITH 
  -- Define surgical admissions and patient demographics
  surgical_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      drg.drg_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON 
      a.hadm_id = drg.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 51 AND 61
      AND drg.drg_type = 'Surgical'
  ),

  -- Calculate medication complexity
  medication_complexity AS (
    SELECT 
      hadm_id,
      COUNT(DISTINCT drug) AS unique_drugs
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY 
      hadm_id
  ),

  -- Stratify by medication complexity quartiles
  medication_complexity_quartiles AS (
    SELECT 
      hadm_id,
      unique_drugs,
      NTILE(4) OVER (ORDER BY unique_drugs) AS quartile
    FROM 
      medication_complexity
  ),

  -- Calculate outcomes
  outcomes AS (
    SELECT 
      sa.hadm_id,
      sa.subject_id,
      sa.dischtime,
      sa.deathtime,
      sa.hospital_expire_flag,
      DATE_DIFF(sa.dischtime, sa.admittime, DAY) AS los,
      CASE 
        WHEN sa.hospital_expire_flag = 1 OR sa.deathtime IS NOT NULL THEN 1 
        ELSE 0 
      END AS in_hospital_mortality
    FROM 
      surgical_admissions sa
  )

-- Final query
SELECT 
  mcq.quartile,
  AVG(o.los) AS los,
  AVG(o.in_hospital_mortality) AS in_hospital_mortality,
  COUNT(DISTINCT o.hadm_id) AS count
FROM 
  outcomes o
JOIN 
  medication_complexity_quartiles mcq
ON 
  o.hadm_id = mcq.hadm_id
GROUP BY 
  mcq.quartile
ORDER BY 
  mcq.quartile;